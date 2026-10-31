defmodule GolfScoring.Competition.Changes.CreateRound do
  @moduledoc false

  use Ash.Resource.Change

  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Repo

  @terminal_event_states ~w(completed archived cancelled)

  @impl true
  def change(changeset, _opts, context) do
    actor_id = if is_map(context.actor), do: Map.get(context.actor, :id), else: nil

    Ash.Changeset.before_action(changeset, fn changeset ->
      event_id = Ash.Changeset.get_attribute(changeset, :event_id)
      course_id = Ash.Changeset.get_attribute(changeset, :course_id)

      with {:ok, _scope} <- EventAuthorityLock.lock_scope!(event_id, [actor_id]),
           :ok <- active_event_admin(actor_id, event_id),
           :ok <- event_accepts_new_round(event_id),
           :ok <- course_accepts_new_round(course_id) do
        changeset
        |> Ash.Changeset.force_change_attribute(:state, :draft)
      else
        {:error, message} ->
          Ash.Changeset.add_error(changeset, field: :event_id, message: message)
      end
    end)
  end

  defp active_event_admin(actor_id, event_id) do
    if ActiveEventRole.authorized?(actor_id, event_id, [:event_admin]) do
      :ok
    else
      {:error, "an active EventAdmin assignment for this Event is required"}
    end
  end

  defp event_accepts_new_round(event_id) do
    case Repo.query!("SELECT state FROM events WHERE id = $1::uuid", [
           Ecto.UUID.dump!(event_id)
         ]).rows do
      [[state]] when state in @terminal_event_states ->
        {:error, "cannot create a Round while the Event is #{state}"}

      [[_state]] ->
        :ok

      [] ->
        {:error, "Event does not exist"}
    end
  end

  defp course_accepts_new_round(course_id) do
    case Repo.query!(
           "SELECT status FROM courses WHERE id = $1::uuid FOR SHARE",
           [Ecto.UUID.dump!(course_id)]
         ).rows do
      [["active"]] -> :ok
      [["archived"]] -> {:error, "cannot create a Round for an archived Course"}
      [] -> {:error, "Course does not exist"}
      _ -> {:error, "Course is not available for a new Round"}
    end
  end
end
