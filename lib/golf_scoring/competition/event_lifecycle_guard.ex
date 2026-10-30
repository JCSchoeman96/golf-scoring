defmodule GolfScoring.Competition.EventLifecycleGuard do
  @moduledoc "Serializes and audits Event lifecycle transitions."

  use Ash.Resource.Change

  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Audit
  alias GolfScoring.Competition.Event
  alias GolfScoring.Repo

  @impl true
  def change(changeset, opts, context) do
    operation = Keyword.fetch!(opts, :operation)
    actor_id = if is_map(context.actor), do: Map.get(context.actor, :id), else: nil

    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      lock_and_transition(changeset, actor_id, operation)
    end)
    |> Ash.Changeset.after_action(fn changeset, event ->
      write_audit(changeset, event, operation)
    end)
  end

  defp lock_and_transition(changeset, actor_id, operation) do
    event_id = changeset.data.id

    with {:ok, scope} <- EventAuthorityLock.lock_scope!(event_id, [actor_id]),
         :ok <- active_event_admin(actor_id, event_id),
         {:ok, next_state} <- transition(scope.event.state, operation) do
      fresh_event = Repo.get!(Event, event_id)

      changeset
      |> Map.put(:data, fresh_event)
      |> Ash.Changeset.set_context(%{
        event_lifecycle_mutation: %{
          actor_id: actor_id,
          event_id: event_id,
          from_state: scope.event.state,
          to_state: next_state
        }
      })
      |> Ash.Changeset.force_change_attribute(:state, state_atom(next_state))
    else
      {:error, message} -> Ash.Changeset.add_error(changeset, field: :state, message: message)
    end
  end

  defp active_event_admin(actor_id, event_id) do
    if ActiveEventRole.authorized?(actor_id, event_id, [:event_admin]) do
      :ok
    else
      {:error, "an active EventAdmin assignment for this Event is required"}
    end
  end

  defp transition("draft", :cancel_event), do: {:ok, "cancelled"}
  defp transition("published", :cancel_event), do: {:ok, "cancelled"}
  defp transition("completed", :archive_event), do: {:ok, "archived"}

  defp transition("draft", :publish_event) do
    {:error, "cannot publish until portal-ready configuration can be verified"}
  end

  defp transition("published", :mark_event_live) do
    {:error, "cannot mark Event live until an operational Round can be verified"}
  end

  defp transition("live", :complete_event) do
    {:error, "cannot complete Event until required Round outcomes can be verified"}
  end

  defp transition(_state, _operation) do
    {:error, "Event cannot make the requested lifecycle transition"}
  end

  defp write_audit(changeset, event, operation) do
    %{event_lifecycle_mutation: mutation} = changeset.context

    attributes = %{
      actor_staff_user_id: mutation.actor_id,
      action: audit_action(operation),
      target_type: "event",
      target_id: mutation.event_id,
      changes: %{"state" => %{"from" => mutation.from_state, "to" => mutation.to_state}}
    }

    case Audit.record_staff_event(attributes, authorize?: false, return_notifications?: true) do
      {:ok, _audit, _notifications} -> {:ok, event}
      {:ok, _audit} -> {:ok, event}
      {:error, error} -> {:error, error}
    end
  end

  defp audit_action(:publish_event), do: "event_published"
  defp audit_action(:mark_event_live), do: "event_marked_live"
  defp audit_action(:complete_event), do: "event_completed"
  defp audit_action(:archive_event), do: "event_archived"
  defp audit_action(:cancel_event), do: "event_cancelled"

  defp state_atom("published"), do: :published
  defp state_atom("live"), do: :live
  defp state_atom("completed"), do: :completed
  defp state_atom("archived"), do: :archived
  defp state_atom("cancelled"), do: :cancelled
end
