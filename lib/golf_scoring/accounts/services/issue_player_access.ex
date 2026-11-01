defmodule GolfScoring.Accounts.Services.IssuePlayerAccess do
  @moduledoc false

  alias Ash.Changeset
  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Accounts.PlayerAccessGrant
  alias GolfScoring.Accounts.PlayerAccessGrantGuard
  alias GolfScoring.Accounts.PlayerAccessToken
  alias GolfScoring.Repo

  @issue_roles [:event_admin, :competition_manager, :registration_staff]

  @spec run(map(), Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, %{grant: PlayerAccessGrant.t(), token: String.t()}} | {:error, term()}
  def run(actor, event_id, player_id, opts \\ []) when is_map(actor) do
    actor_id = Map.get(actor, :id)
    expires_at = Keyword.get(opts, :expires_at)

    Repo.transaction(fn ->
      with {:ok, _scope} <- EventAuthorityLock.lock_scope!(event_id, [actor_id]),
           :ok <- authorize(actor_id, event_id),
           {:ok, _event} <- PlayerAccessGrantGuard.lock_event(Repo, event_id),
           {:ok, _player} <- PlayerAccessGrantGuard.lock_player(Repo, player_id),
           :ok <- require_event_player_membership(event_id, player_id),
           {:ok, grant_or_none} <- lock_and_expire_active(event_id, player_id),
           :ok <- reject_existing_active(grant_or_none),
           {:ok, result} <- create_grant(event_id, player_id, expires_at) do
        result
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_result()
  end

  defp authorize(actor_id, event_id) do
    if ActiveEventRole.authorized?(actor_id, event_id, @issue_roles) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp require_event_player_membership(event_id, player_id) do
    if PlayerAccessGrantGuard.event_player_round_entry_exists?(Repo, event_id, player_id) do
      :ok
    else
      {:error, :player_not_in_event}
    end
  end

  defp lock_and_expire_active(event_id, player_id) do
    case PlayerAccessGrantGuard.lock_active_grant_for_event_player(Repo, event_id, player_id) do
      {:ok, grant} ->
        case PlayerAccessGrantGuard.lazy_expire_if_due!(grant) do
          {:ok, updated} -> {:ok, updated}
          {:error, reason} -> {:error, reason}
        end

      {:error, :no_active_grant} ->
        {:ok, nil}
    end
  end

  defp reject_existing_active(nil), do: :ok

  defp reject_existing_active(%{state: :active}), do: {:error, :active_player_access_exists}

  defp reject_existing_active(_), do: :ok

  defp create_grant(event_id, player_id, expires_at) do
    {token, digest} = PlayerAccessToken.generate()

    attrs = %{
      event_id: event_id,
      player_id: player_id,
      token_digest: digest,
      state: :active,
      expires_at: expires_at
    }

    case PlayerAccessGrant
         |> Changeset.for_create(:create_internal, attrs)
         |> Ash.create(authorize?: false) do
      {:ok, grant} -> {:ok, %{grant: grant, token: token}}
      {:error, error} -> {:error, normalize_create_error(error)}
    end
  end

  defp normalize_create_error(%{errors: errors}) do
    case Enum.find(errors, fn
           %{caused_by: %{reason: %Postgrex.Error{} = err}} -> err
           _ -> nil
         end) do
      %{caused_by: %{reason: %Postgrex.Error{postgres: %{code: :unique_violation}}}} ->
        :active_player_access_exists

      _ ->
        :grant_create_failed
    end
  end

  defp normalize_create_error(other), do: other

  defp normalize_result({:ok, result}), do: {:ok, result}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result({:error, :rollback, reason}), do: {:error, reason}
end
