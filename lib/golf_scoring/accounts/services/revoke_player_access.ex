defmodule GolfScoring.Accounts.Services.RevokePlayerAccess do
  @moduledoc false

  alias Ash.Changeset
  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Accounts.PlayerAccessGrant
  alias GolfScoring.Accounts.PlayerAccessGrantGuard
  alias GolfScoring.Audit
  alias GolfScoring.Repo

  @revoke_roles [:event_admin, :competition_manager]

  @spec run(map(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, PlayerAccessGrant.t()} | {:error, term()}
  def run(actor, event_id, player_id) when is_map(actor) do
    actor_id = Map.get(actor, :id)

    Repo.transaction(fn ->
      with {:ok, _scope} <- EventAuthorityLock.lock_scope!(event_id, [actor_id]),
           :ok <- authorize(actor_id, event_id),
           {:ok, _event} <- PlayerAccessGrantGuard.lock_event(Repo, event_id),
           {:ok, current} <- lock_usable_active(event_id, player_id),
           {:ok, revoked} <- mark_revoked(current.id),
           :ok <- write_revoke_audit(actor_id, event_id, player_id, revoked) do
        revoked
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_result()
  end

  defp authorize(actor_id, event_id) do
    if ActiveEventRole.authorized?(actor_id, event_id, @revoke_roles) do
      :ok
    else
      {:error, :forbidden}
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

  defp mark_revoked(grant_id) do
    PlayerAccessGrant
    |> Ash.get!(grant_id, authorize?: false)
    |> Changeset.for_update(:mark_revoked_internal, %{})
    |> Ash.update(authorize?: false)
    |> case do
      {:ok, row} -> {:ok, row}
      {:error, error} -> {:error, error}
    end
  end

  defp write_revoke_audit(actor_id, event_id, player_id, revoked) do
    case Audit.record_staff_event(
           %{
             actor_staff_user_id: actor_id,
             action: "revoke_player_access",
             target_type: "Player",
             target_id: player_id,
             context: %{
               event_id: event_id
             },
             changes: %{
               revoked_grant_id: revoked.id
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
