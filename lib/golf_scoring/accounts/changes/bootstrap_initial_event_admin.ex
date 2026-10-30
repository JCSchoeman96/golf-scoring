defmodule GolfScoring.Accounts.Changes.BootstrapInitialEventAdmin do
  @moduledoc false

  use Ash.Resource.Change

  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Competition.Event
  alias GolfScoring.Repo

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.change_attribute(:role, :event_admin)
    |> Ash.Changeset.before_action(fn changeset ->
      event_id = Ash.Changeset.get_attribute(changeset, :event_id)
      staff_user_id = Ash.Changeset.get_attribute(changeset, :staff_user_id)

      with :ok <- event_accepts_bootstrap(event_id),
           :ok <- staff_is_active(staff_user_id) do
        Ash.Changeset.force_change_attribute(changeset, :status, :active)
      else
        {:error, message} ->
          Ash.Changeset.add_error(changeset, field: :event_id, message: message)
      end
    end)
  end

  defp event_accepts_bootstrap(event_id) do
    case Repo.get(Event, event_id) do
      %{state: :draft} -> :ok
      nil -> {:error, "Event must exist"}
      _ -> {:error, "initial Event Admin can only be bootstrapped for a draft Event"}
    end
  end

  defp staff_is_active(staff_user_id) do
    case Repo.get(StaffUser, staff_user_id) do
      %{status: :active} -> :ok
      nil -> {:error, "StaffUser must exist"}
      _ -> {:error, "StaffUser must be active"}
    end
  end
end
