defmodule GolfScoring.Accounts.StaffLifecycleGuard do
  @moduledoc "Serializes and audits ordinary StaffUser lifecycle transitions."

  use Ash.Resource.Change

  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Accounts.SystemAdminGuard
  alias GolfScoring.Audit
  alias GolfScoring.Repo

  @impl true
  def change(changeset, opts, context) do
    operation = Keyword.fetch!(opts, :operation)
    actor = context.actor

    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      lock_and_apply_transition(changeset, actor, operation)
    end)
    |> Ash.Changeset.after_action(fn changeset, target ->
      write_audit(changeset, target, operation)
    end)
  end

  defp lock_and_apply_transition(changeset, actor, operation) do
    :ok = SystemAdminGuard.acquire_lock!()

    target_id = changeset.data.id
    actor_id = if is_map(actor), do: Map.get(actor, :id), else: nil
    locked_users = lock_staff_users([actor_id, target_id])
    actor_row = Map.get(locked_users, actor_id)
    target_row = Map.get(locked_users, target_id)

    with :ok <- active_system_admin(actor_row),
         {:ok, next_status} <- transition(target_row, operation),
         :ok <- active_admin_remains(target_row, next_status) do
      fresh_target = Repo.get!(StaffUser, target_id)

      changeset
      |> Map.put(:data, fresh_target)
      |> Ash.Changeset.set_context(%{
        staff_lifecycle: %{actor_id: actor_row.id, from_status: target_row.status}
      })
      |> Ash.Changeset.force_change_attribute(:status, status_atom(next_status))
    else
      {:error, message} ->
        Ash.Changeset.add_error(changeset, field: :status, message: message)
    end
  end

  defp lock_staff_users(ids) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort_by(&Ecto.UUID.dump!/1)
    |> Map.new(fn id ->
      result =
        Repo.query!(
          """
          SELECT id::text, status, system_admin
          FROM staff_users
          WHERE id = $1::uuid
          FOR UPDATE
          """,
          [Ecto.UUID.dump!(id)]
        )

      case result.rows do
        [[row_id, status, system_admin]] ->
          {id, %{id: row_id, status: status, system_admin: system_admin}}

        [] ->
          {id, nil}
      end
    end)
  end

  defp active_system_admin(%{status: "active", system_admin: true}), do: :ok

  defp active_system_admin(_actor) do
    {:error, "an active SYSTEM_ADMIN is required"}
  end

  defp transition(%{status: "active"}, :suspend), do: {:ok, "suspended"}
  defp transition(%{status: "suspended"}, :reactivate), do: {:ok, "active"}

  defp transition(%{status: status}, :disable) when status in ["active", "suspended"] do
    {:ok, "disabled"}
  end

  defp transition(nil, _operation), do: {:error, "target StaffUser does not exist"}

  defp transition(_target, _operation) do
    {:error, "StaffUser cannot make the requested lifecycle transition"}
  end

  defp active_admin_remains(%{status: "active", system_admin: true}, next_status)
       when next_status in ["suspended", "disabled"] do
    case Repo.query!(
           "SELECT count(*) FROM staff_users WHERE status = 'active' AND system_admin = TRUE"
         ).rows do
      [[count]] when count > 1 -> :ok
      [[_count]] -> {:error, "cannot remove the last active SYSTEM_ADMIN"}
    end
  end

  defp active_admin_remains(_target, _next_status), do: :ok

  defp write_audit(changeset, target, operation) do
    %{staff_lifecycle: %{actor_id: actor_id, from_status: from_status}} = changeset.context
    to_status = status_string(target.status)

    attributes = %{
      actor_staff_user_id: actor_id,
      action: audit_action(operation),
      target_type: "staff_user",
      target_id: target.id,
      changes: %{"status" => %{"from" => from_status, "to" => to_status}}
    }

    case Audit.record_staff_event(attributes, authorize?: false, return_notifications?: true) do
      {:ok, _event, _notifications} -> {:ok, target}
      {:ok, _event} -> {:ok, target}
      {:error, error} -> {:error, error}
    end
  end

  defp audit_action(:suspend), do: "staff_user_suspended"
  defp audit_action(:reactivate), do: "staff_user_reactivated"
  defp audit_action(:disable), do: "staff_user_disabled"

  defp status_atom("active"), do: :active
  defp status_atom("suspended"), do: :suspended
  defp status_atom("disabled"), do: :disabled

  defp status_string(status) when status in [:active, :suspended, :disabled],
    do: Atom.to_string(status)
end
