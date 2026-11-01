defmodule GolfScoring.Accounts.Services.ReissuePlayerAccess do
  @moduledoc false

  alias Ash.Changeset
  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Accounts.PlayerAccessGrant
  alias GolfScoring.Accounts.PlayerAccessGrantGuard
  alias GolfScoring.Accounts.PlayerAccessToken
  alias GolfScoring.Audit
  alias GolfScoring.Repo

  @reissue_roles [:event_admin, :competition_manager, :registration_staff, :scoring_support]

  @spec run(map(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, %{grant: PlayerAccessGrant.t(), token: String.t()}} | {:error, term()}
  def run(actor, event_id, player_id) when is_map(actor) do
    actor_id = Map.get(actor, :id)

    Repo.transaction(fn ->
      with {:ok, _scope} <- EventAuthorityLock.lock_scope!(event_id, [actor_id]),
           :ok <- authorize(actor_id, event_id),
           {:ok, _event} <- PlayerAccessGrantGuard.lock_event(Repo, event_id),
           {:ok, _player} <- PlayerAccessGrantGuard.lock_player(Repo, player_id),
           :ok <- require_event_player_membership(event_id, player_id),
           {:ok, current} <- lock_usable_active(event_id, player_id),
           {:ok, superseded} <- mark_superseded(current.id),
           {:ok, result} <- create_replacement(event_id, player_id, current),
           :ok <- write_reissue_audit(actor_id, event_id, player_id, superseded, result.grant) do
        result
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_result()
  end

  defp authorize(actor_id, event_id) do
    if ActiveEventRole.authorized?(actor_id, event_id, @reissue_roles) do
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

  defp lock_usable_active(event_id, player_id) do
    with {:ok, grant} <-
           PlayerAccessGrantGuard.lock_active_grant_for_event_player(Repo, event_id, player_id),
         {:ok, grant} <- PlayerAccessGrantGuard.lazy_expire_if_due!(grant),
         true <- grant.state == :active do
      {:ok, grant}
    else
      {:error, :no_active_grant} -> {:error, :no_active_player_access}
      false -> {:error, :no_active_player_access}
      {:error, reason} -> {:error, reason}
    end
  end

  defp mark_superseded(grant_id) do
    PlayerAccessGrant
    |> Ash.get!(grant_id, authorize?: false)
    |> Changeset.for_update(:mark_superseded_internal, %{})
    |> Ash.update(authorize?: false)
    |> case do
      {:ok, row} -> {:ok, row}
      {:error, error} -> {:error, error}
    end
  end

  defp create_replacement(event_id, player_id, previous) do
    {token, digest} = PlayerAccessToken.generate()

    attrs = %{
      event_id: event_id,
      player_id: player_id,
      token_digest: digest,
      state: :active,
      expires_at: previous.expires_at
    }

    case PlayerAccessGrant
         |> Changeset.for_create(:create_internal, attrs)
         |> Ash.create(authorize?: false) do
      {:ok, grant} -> {:ok, %{grant: grant, token: token}}
      {:error, error} -> {:error, error}
    end
  end

  defp write_reissue_audit(actor_id, event_id, player_id, superseded, replacement) do
    case Audit.record_staff_event(
           %{
             actor_staff_user_id: actor_id,
             action: "reissue_player_access",
             target_type: "Player",
             target_id: player_id,
             context: %{
               event_id: event_id
             },
             changes: %{
               superseded_grant_id: superseded.id,
               replacement_grant_id: replacement.id
             }
           },
           authorize?: false
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_result({:ok, result}), do: {:ok, result}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result({:error, :rollback, reason}), do: {:error, reason}
end
