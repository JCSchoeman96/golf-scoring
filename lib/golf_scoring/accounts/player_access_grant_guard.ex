defmodule GolfScoring.Accounts.PlayerAccessGrantGuard do
  @moduledoc false

  alias Ash.Changeset
  alias GolfScoring.Accounts.PlayerAccessGrant
  alias GolfScoring.Repo

  @active_state "active"

  @spec event_player_round_entry_exists?(Ecto.Repo.t(), Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  def event_player_round_entry_exists?(repo \\ Repo, event_id, player_id) do
    case repo.query!(
           """
           SELECT EXISTS (
             SELECT 1 FROM round_entries
             WHERE event_id = $1::uuid AND player_id = $2::uuid
           )
           """,
           [Ecto.UUID.dump!(event_id), Ecto.UUID.dump!(player_id)]
         ).rows do
      [[true]] -> true
      [[false]] -> false
    end
  end

  @spec lock_event(Ecto.Repo.t(), Ecto.UUID.t()) :: {:ok, map()} | {:error, :event_not_found}
  def lock_event(repo, event_id) do
    case repo.query!(
           "SELECT id::text FROM events WHERE id = $1::uuid FOR UPDATE",
           [Ecto.UUID.dump!(event_id)]
         ).rows do
      [[id]] -> {:ok, %{id: Ecto.UUID.cast!(id)}}
      [] -> {:error, :event_not_found}
    end
  end

  @spec lock_player(Ecto.Repo.t(), Ecto.UUID.t()) :: {:ok, map()} | {:error, :player_not_found}
  def lock_player(repo, player_id) do
    case repo.query!(
           "SELECT id::text FROM players WHERE id = $1::uuid FOR UPDATE",
           [Ecto.UUID.dump!(player_id)]
         ).rows do
      [[id]] -> {:ok, %{id: Ecto.UUID.cast!(id)}}
      [] -> {:error, :player_not_found}
    end
  end

  @spec lock_active_grant_for_event_player(Ecto.Repo.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, map()} | {:error, :no_active_grant}
  def lock_active_grant_for_event_player(repo, event_id, player_id) do
    case repo.query!(
           """
           SELECT id::text, event_id::text, player_id::text, state, expires_at
           FROM player_access_grants
           WHERE event_id = $1::uuid AND player_id = $2::uuid AND state = $3
           FOR UPDATE
           """,
           [Ecto.UUID.dump!(event_id), Ecto.UUID.dump!(player_id), @active_state]
         ).rows do
      [[id, event_id, player_id, state, expires_at]] ->
        {:ok,
         %{
           id: Ecto.UUID.cast!(id),
           event_id: Ecto.UUID.cast!(event_id),
           player_id: Ecto.UUID.cast!(player_id),
           state: String.to_existing_atom(state),
           expires_at: expires_at
         }}

      [] ->
        {:error, :no_active_grant}
    end
  end

  @spec grant_expired?(map(), DateTime.t()) :: boolean()
  def grant_expired?(%{expires_at: nil}, _now), do: false

  def grant_expired?(%{expires_at: expires_at}, %DateTime{} = now) do
    DateTime.compare(normalize_expires_at(expires_at), now) != :gt
  end

  defp normalize_expires_at(%NaiveDateTime{} = naive),
    do: naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:microsecond)

  defp normalize_expires_at(%DateTime{} = dt), do: DateTime.truncate(dt, :microsecond)

  @spec lazy_expire_if_due!(map(), DateTime.t()) :: {:ok, map()} | {:error, term()}
  def lazy_expire_if_due!(grant, now \\ DateTime.utc_now())

  def lazy_expire_if_due!(%{state: :active} = grant, now) do
    if grant_expired?(grant, now) do
      case mark_expired(grant.id) do
        {:ok, expired} -> {:ok, Map.put(expired, :state, :expired)}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, grant}
    end
  end

  def lazy_expire_if_due!(grant, _now), do: {:ok, grant}

  @spec apply_lazy_expiry_for_digest(Ecto.Repo.t(), binary(), DateTime.t()) ::
          :ok | {:error, term()}
  def apply_lazy_expiry_for_digest(repo, digest, now \\ DateTime.utc_now()) do
    case repo.query!(
           """
           SELECT id::text, event_id::text, player_id::text, state, expires_at
           FROM player_access_grants
           WHERE token_digest = $1 AND state = $2
           FOR UPDATE
           """,
           [digest, @active_state]
         ).rows do
      [[id, event_id, player_id, state, expires_at]] ->
        grant = %{
          id: Ecto.UUID.cast!(id),
          event_id: Ecto.UUID.cast!(event_id),
          player_id: Ecto.UUID.cast!(player_id),
          state: String.to_existing_atom(state),
          expires_at: expires_at
        }

        case lazy_expire_if_due!(grant, now) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      [] ->
        :ok
    end
  end

  @spec find_usable_active_by_digest(Ecto.Repo.t(), binary(), DateTime.t()) ::
          {:ok, map()} | {:error, :invalid_credentials}
  def find_usable_active_by_digest(repo, digest, now \\ DateTime.utc_now()) do
    case repo.query!(
           """
           SELECT id::text, event_id::text, player_id::text, state, expires_at
           FROM player_access_grants
           WHERE token_digest = $1 AND state = $2
           FOR UPDATE
           """,
           [digest, @active_state]
         ).rows do
      [[id, event_id, player_id, state, expires_at]] ->
        grant = %{
          id: Ecto.UUID.cast!(id),
          event_id: Ecto.UUID.cast!(event_id),
          player_id: Ecto.UUID.cast!(player_id),
          state: String.to_existing_atom(state),
          expires_at: expires_at
        }

        if grant_expired?(grant, now) do
          {:error, :invalid_credentials}
        else
          {:ok, grant}
        end

      [] ->
        {:error, :invalid_credentials}
    end
  end

  @spec find_active_by_digest(Ecto.Repo.t(), binary(), DateTime.t()) ::
          {:ok, map()} | {:error, :invalid_credentials}
  def find_active_by_digest(repo, digest, now \\ DateTime.utc_now()) do
    case apply_lazy_expiry_for_digest(repo, digest, now) do
      :ok -> find_usable_active_by_digest(repo, digest, now)
      {:error, _} -> {:error, :invalid_credentials}
    end
  end

  @spec apply_lazy_expiry_for_grant_id(Ecto.Repo.t(), Ecto.UUID.t(), DateTime.t()) ::
          :ok | {:error, term()}
  def apply_lazy_expiry_for_grant_id(repo, grant_id, now \\ DateTime.utc_now()) do
    case repo.query!(
           """
           SELECT id::text, event_id::text, player_id::text, state, expires_at
           FROM player_access_grants
           WHERE id = $1::uuid
           FOR UPDATE
           """,
           [Ecto.UUID.dump!(grant_id)]
         ).rows do
      [[id, event_id, player_id, state, expires_at]] ->
        grant = grant_row_to_map(id, event_id, player_id, state, expires_at)
        active_grant_lazy_expiry(grant, now)

      [] ->
        :ok
    end
  end

  @spec load_grant_for_session(Ecto.UUID.t(), DateTime.t()) ::
          {:ok, PlayerAccessGrant.t()} | {:error, :invalid_player_session}
  def load_grant_for_session(grant_id, now \\ DateTime.utc_now()) do
    case run_lazy_expiry_for_session(grant_id, now) do
      :ok -> load_usable_grant_for_session(grant_id, now)
      :expiry_failed -> {:error, :invalid_player_session}
    end
  end

  defp active_grant_lazy_expiry(%{state: :active} = grant, now) do
    case lazy_expire_if_due!(grant, now) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp active_grant_lazy_expiry(_grant, _now), do: :ok

  defp run_lazy_expiry_for_session(grant_id, now) do
    grant_id
    |> lazy_expiry_for_session_tx(now)
    |> transaction_lazy_expiry_result()
  end

  defp lazy_expiry_for_session_tx(grant_id, now) do
    Repo.transaction(fn ->
      apply_lazy_expiry_for_grant_id(Repo, grant_id, now)
      |> lazy_expiry_tx_result()
    end)
  end

  defp lazy_expiry_tx_result(:ok), do: :ok
  defp lazy_expiry_tx_result({:error, reason}), do: Repo.rollback(reason)

  defp transaction_lazy_expiry_result({:ok, :ok}), do: :ok
  defp transaction_lazy_expiry_result({:error, _reason}), do: :expiry_failed

  defp load_usable_grant_for_session(grant_id, now) do
    case Ash.get(PlayerAccessGrant, grant_id, authorize?: false) do
      {:ok, %{state: :active} = grant} ->
        if grant_expired?(grant, now) do
          {:error, :invalid_player_session}
        else
          {:ok, grant}
        end

      _ ->
        {:error, :invalid_player_session}
    end
  end

  defp grant_row_to_map(id, event_id, player_id, state, expires_at) do
    %{
      id: Ecto.UUID.cast!(id),
      event_id: Ecto.UUID.cast!(event_id),
      player_id: Ecto.UUID.cast!(player_id),
      state: String.to_existing_atom(state),
      expires_at: expires_at
    }
  end

  defp mark_expired(grant_id) do
    PlayerAccessGrant
    |> Ash.get!(grant_id, authorize?: false)
    |> Changeset.for_update(:mark_expired_internal, %{})
    |> Ash.update(authorize?: false)
  end
end
