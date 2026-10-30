defmodule GolfScoring.Accounts.EventStaffAssignmentGuard do
  @moduledoc "Serializes Event staff role changes and writes their audit records."

  use Ash.Resource.Change

  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Audit
  alias GolfScoring.Repo

  @impl true
  def change(changeset, opts, context) do
    operation = Keyword.fetch!(opts, :operation)
    actor_id = if is_map(context.actor), do: Map.get(context.actor, :id), else: nil

    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      lock_and_validate(changeset, actor_id, operation)
    end)
    |> Ash.Changeset.after_action(fn changeset, assignment ->
      write_audit(changeset, assignment, operation)
    end)
  end

  defp lock_and_validate(changeset, actor_id, :assign) do
    event_id = input(changeset, :event_id)
    staff_user_id = input(changeset, :staff_user_id)
    role = input(changeset, :role)

    with {:ok, scope} <- EventAuthorityLock.lock_scope!(event_id, [actor_id, staff_user_id]),
         :ok <- active_event_admin(actor_id, event_id),
         :ok <- event_accepts_assignment(scope.event),
         :ok <- active_target(scope, staff_user_id),
         :ok <- role_is_available(scope, staff_user_id, role) do
      changeset
      |> Ash.Changeset.set_context(%{
        event_staff_mutation: %{
          actor_id: actor_id,
          event_id: event_id,
          staff_user_id: staff_user_id,
          role: Atom.to_string(role),
          from_status: nil,
          to_status: "active"
        }
      })
      |> Ash.Changeset.force_change_attribute(:status, :active)
    else
      {:error, message} -> Ash.Changeset.add_error(changeset, field: :event_id, message: message)
    end
  end

  defp lock_and_validate(changeset, actor_id, :revoke) do
    assignment = changeset.data
    event_id = assignment.event_id
    staff_user_id = assignment.staff_user_id

    with {:ok, scope} <-
           EventAuthorityLock.lock_scope!(event_id, [actor_id, staff_user_id], [assignment.id]),
         :ok <- active_event_admin(actor_id, event_id),
         %{status: "active"} = locked_assignment <-
           EventAuthorityLock.assignment(scope, assignment.id),
         :ok <- may_revoke(scope, locked_assignment) do
      changeset
      |> Map.put(:data, Repo.get!(GolfScoring.Accounts.EventStaffAssignment, assignment.id))
      |> Ash.Changeset.set_context(%{
        event_staff_mutation: %{
          actor_id: actor_id,
          event_id: event_id,
          staff_user_id: locked_assignment.staff_user_id,
          role: locked_assignment.role,
          assignment_id: assignment.id,
          from_status: "active",
          to_status: "revoked"
        }
      })
      |> Ash.Changeset.force_change_attribute(:status, :revoked)
    else
      {:error, message} -> Ash.Changeset.add_error(changeset, field: :status, message: message)
      _ -> Ash.Changeset.add_error(changeset, field: :status, message: "assignment is not active")
    end
  end

  defp active_event_admin(actor_id, event_id) do
    if ActiveEventRole.authorized?(actor_id, event_id, [:event_admin]) do
      :ok
    else
      {:error, "an active EventAdmin assignment for this Event is required"}
    end
  end

  defp event_accepts_assignment(%{state: "archived"}) do
    {:error, "cannot assign a role to an archived Event"}
  end

  defp event_accepts_assignment(_event), do: :ok

  defp active_target(scope, staff_user_id) do
    case EventAuthorityLock.staff_user(scope, staff_user_id) do
      %{status: "active"} -> :ok
      _ -> {:error, "target StaffUser must be active"}
    end
  end

  defp role_is_available(scope, staff_user_id, role)
       when role in [
              :event_admin,
              :competition_manager,
              :registration_staff,
              :scoring_support
            ] do
    role = Atom.to_string(role)

    if Enum.any?(scope.assignments, fn assignment ->
         assignment.staff_user_id == staff_user_id and assignment.role == role and
           assignment.status == "active"
       end) do
      {:error, "StaffUser already has this active Event role"}
    else
      :ok
    end
  end

  defp role_is_available(_scope, _staff_user_id, _role) do
    {:error, "role is not an allowed Event staff role"}
  end

  defp may_revoke(scope, %{role: "event_admin", staff_user_id: staff_user_id}) do
    case EventAuthorityLock.staff_user(scope, staff_user_id) do
      %{status: "active"} ->
        if EventAuthorityLock.effective_event_admin_count(scope) > 1 do
          :ok
        else
          {:error, "cannot revoke the final effective EventAdmin assignment"}
        end

      _ ->
        :ok
    end
  end

  defp may_revoke(_scope, _assignment), do: :ok

  defp input(changeset, attribute) do
    Map.get(changeset.attributes, attribute) || Ash.Changeset.get_attribute(changeset, attribute)
  end

  defp write_audit(changeset, assignment, operation) do
    %{event_staff_mutation: mutation} = changeset.context
    event_staff_audit(mutation, assignment, operation)
  end

  defp event_staff_audit(mutation, assignment, :assign) do
    record_audit(mutation, assignment, "event_staff_role_assigned")
  end

  defp event_staff_audit(mutation, assignment, :revoke) do
    record_audit(mutation, assignment, "event_staff_role_revoked")
  end

  defp record_audit(mutation, assignment, action) do
    attributes = %{
      actor_staff_user_id: mutation.actor_id,
      action: action,
      target_type: "event",
      target_id: mutation.event_id,
      context: %{
        "event_id" => mutation.event_id,
        "staff_user_id" => mutation.staff_user_id,
        "role" => mutation.role,
        "assignment_id" => assignment.id
      },
      changes: %{
        "role" => mutation.role,
        "status" => %{"from" => mutation.from_status, "to" => mutation.to_status}
      }
    }

    case Audit.record_staff_event(attributes, authorize?: false, return_notifications?: true) do
      {:ok, _event, _notifications} -> {:ok, assignment}
      {:ok, _event} -> {:ok, assignment}
      {:error, error} -> {:error, error}
    end
  end
end
