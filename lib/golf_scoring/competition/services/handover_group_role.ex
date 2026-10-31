defmodule GolfScoring.Competition.Services.HandoverGroupRole do
  @moduledoc false

  alias Ash.Changeset
  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Audit
  alias GolfScoring.Competition.GroupRoleAssignment
  alias GolfScoring.Competition.GroupRoleAssignmentGuard
  alias GolfScoring.Competition.StartingParticipant
  alias GolfScoring.Repo

  @handover_roles [:event_admin, :competition_manager, :scoring_support]
  @pre_open_round_states ~w(draft ready)

  @spec run(map(), Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), atom()) ::
          {:ok, GroupRoleAssignment.t()} | {:error, term()}
  def run(actor, event_id, round_id, playing_group_id, replacement_entry_id, role)
      when role in [:primary_scorer, :designated_verifier] and is_map(actor) do
    actor_id = Map.get(actor, :id)

    Repo.transaction(fn ->
      with {:ok, _scope} <- EventAuthorityLock.lock_scope!(event_id, [actor_id]),
           :ok <- authorize(actor_id, event_id),
           {:ok, round} <- lock_round(round_id),
           :ok <- round_belongs_to_event(round, event_id),
           :ok <- round_accepts_handover(round),
           {:ok, group} <- lock_playing_group(playing_group_id),
           :ok <- group_belongs_to_round(group, round_id),
           {:ok, current} <-
             GroupRoleAssignmentGuard.lock_active_assignment_for_group_role(
               Repo,
               playing_group_id,
               role
             ),
           :ok <- GroupRoleAssignmentGuard.lock_active_assignments_for_group(Repo, group.id),
           {:ok, replacement} <- lock_round_entry(replacement_entry_id),
           :ok <- entry_belongs_to_round(replacement, round_id, event_id),
           :ok <- entry_in_group(replacement, playing_group_id),
           :ok <- validate_start_eligible(replacement),
           :ok <- ensure_different_holder(current, replacement.id),
           :ok <- ensure_entry_not_other_role(group.id, replacement.id, role),
           {:ok, _handed_over} <- mark_handed_over(current.id),
           {:ok, new_assignment} <- create_successor(group, replacement, role, current),
           :ok <-
             write_handover_audit(actor_id, round_id, group.id, role, current, new_assignment) do
        new_assignment
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_result()
  end

  def run(_actor, _event_id, _round_id, _playing_group_id, _replacement_entry_id, _role),
    do: {:error, :invalid_input}

  defp authorize(actor_id, event_id) do
    if ActiveEventRole.authorized?(actor_id, event_id, @handover_roles) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp lock_round(round_id) do
    case Repo.query!(
           "SELECT id::text, event_id::text, state FROM rounds WHERE id = $1::uuid FOR UPDATE",
           [Ecto.UUID.dump!(round_id)]
         ).rows do
      [[id, event_id, state]] ->
        {:ok,
         %{
           id: Ecto.UUID.cast!(id),
           event_id: Ecto.UUID.cast!(event_id),
           state: state
         }}

      [] ->
        {:error, :round_not_found}
    end
  end

  defp round_belongs_to_event(%{event_id: round_event_id}, event_id) do
    if round_event_id == event_id, do: :ok, else: {:error, :event_mismatch}
  end

  defp round_accepts_handover(%{state: state}) when state in @pre_open_round_states, do: :ok

  defp round_accepts_handover(%{state: state}),
    do: {:error, {:invalid_round_state, state}}

  defp lock_playing_group(playing_group_id) do
    case Repo.query!(
           """
           SELECT id::text, round_id::text
           FROM playing_groups
           WHERE id = $1::uuid
           FOR UPDATE
           """,
           [Ecto.UUID.dump!(playing_group_id)]
         ).rows do
      [[id, round_id]] ->
        {:ok, %{id: Ecto.UUID.cast!(id), round_id: Ecto.UUID.cast!(round_id)}}

      [] ->
        {:error, :playing_group_not_found}
    end
  end

  defp group_belongs_to_round(%{round_id: group_round_id}, round_id) do
    if group_round_id == round_id, do: :ok, else: {:error, :playing_group_mismatch}
  end

  defp lock_round_entry(round_entry_id) do
    case Repo.query!(
           """
           SELECT id::text, event_id::text, round_id::text, player_id::text,
                  registration_status, participation_status, playing_group_id::text
           FROM round_entries
           WHERE id = $1::uuid
           FOR UPDATE
           """,
           [Ecto.UUID.dump!(round_entry_id)]
         ).rows do
      [[id, event_id, round_id, _player_id, registration_status, participation_status, group_id]] ->
        {:ok,
         %{
           id: Ecto.UUID.cast!(id),
           event_id: Ecto.UUID.cast!(event_id),
           round_id: Ecto.UUID.cast!(round_id),
           registration_status: registration_atom(registration_status),
           participation_status: participation_atom(participation_status),
           playing_group_id: cast_optional_uuid(group_id)
         }}

      [] ->
        {:error, :round_entry_not_found}
    end
  end

  defp cast_optional_uuid(nil), do: nil

  defp cast_optional_uuid(value) do
    {:ok, uuid} = Ecto.UUID.cast(value)
    uuid
  end

  defp entry_belongs_to_round(entry, round_id, event_id) do
    if entry.round_id == round_id and entry.event_id == event_id do
      :ok
    else
      {:error, :round_entry_mismatch}
    end
  end

  defp entry_in_group(%{playing_group_id: group_id}, playing_group_id)
       when group_id == playing_group_id,
       do: :ok

  defp entry_in_group(_, _), do: {:error, :round_entry_not_in_playing_group}

  defp validate_start_eligible(entry) do
    if StartingParticipant.current_starting_participant?(entry) do
      :ok
    else
      {:error, :not_current_starting_participant}
    end
  end

  defp ensure_different_holder(%{round_entry_id: current_entry_id}, replacement_entry_id)
       when current_entry_id == replacement_entry_id,
       do: {:error, :handover_requires_different_entry}

  defp ensure_different_holder(_, _), do: :ok

  defp ensure_entry_not_other_role(playing_group_id, round_entry_id, role) do
    if GroupRoleAssignmentGuard.entry_holds_other_active_role?(
         Repo,
         playing_group_id,
         round_entry_id,
         role
       ) do
      {:error, :round_entry_already_holds_other_active_role}
    else
      :ok
    end
  end

  defp mark_handed_over(assignment_id) do
    GroupRoleAssignment
    |> Ash.get!(assignment_id, authorize?: false)
    |> Changeset.for_update(:mark_handed_over_internal, %{})
    |> Ash.update(authorize?: false)
    |> case do
      {:ok, row} -> {:ok, row}
      {:error, error} -> {:error, error}
    end
  end

  defp create_successor(group, replacement, role, current) do
    version = current.assignment_version + 1

    GroupRoleAssignment
    |> Changeset.for_create(:create_internal, %{
      round_id: group.round_id,
      playing_group_id: group.id,
      round_entry_id: replacement.id,
      role: role,
      state: :active,
      assignment_version: version
    })
    |> Ash.create(authorize?: false)
    |> case do
      {:ok, assignment} -> {:ok, assignment}
      {:error, error} -> {:error, error}
    end
  end

  defp write_handover_audit(actor_id, round_id, playing_group_id, role, previous, successor) do
    case Audit.record_staff_event(
           %{
             actor_staff_user_id: actor_id,
             action: "handover_group_role",
             target_type: "PlayingGroup",
             target_id: playing_group_id,
             context: %{
               round_id: round_id,
               role: to_string(role)
             },
             changes: %{
               previous_assignment_id: previous.id,
               previous_round_entry_id: previous.round_entry_id,
               previous_assignment_version: previous.assignment_version,
               successor_assignment_id: successor.id,
               successor_round_entry_id: successor.round_entry_id,
               successor_assignment_version: successor.assignment_version
             }
           },
           authorize?: false
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp registration_atom("expected"), do: :expected
  defp registration_atom("checked_in"), do: :checked_in
  defp registration_atom("no_show"), do: :no_show
  defp registration_atom("withdrawn_before_start"), do: :withdrawn_before_start
  defp registration_atom("replaced_before_start"), do: :replaced_before_start

  defp participation_atom("not_started"), do: :not_started
  defp participation_atom("active"), do: :active
  defp participation_atom("completed"), do: :completed
  defp participation_atom("withdrawn"), do: :withdrawn
  defp participation_atom("disqualified"), do: :disqualified

  defp normalize_result({:ok, result}), do: {:ok, result}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result({:error, :rollback, reason}), do: {:error, reason}
end
