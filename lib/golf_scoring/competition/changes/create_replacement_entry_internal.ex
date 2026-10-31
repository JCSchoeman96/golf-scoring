defmodule GolfScoring.Competition.Changes.CreateReplacementEntryInternal do
  @moduledoc false

  use Ash.Resource.Change

  alias GolfScoring.Competition.Player
  alias GolfScoring.Repo

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      player_id = Ash.Changeset.get_attribute(changeset, :player_id)

      case player_exists(player_id) do
        :ok ->
          changeset
          |> Ash.Changeset.force_change_attribute(:registration_status, :expected)
          |> Ash.Changeset.force_change_attribute(:participation_status, :not_started)

        {:error, message} ->
          Ash.Changeset.add_error(changeset, field: :player_id, message: message)
      end
    end)
  end

  defp player_exists(player_id) do
    case Repo.get(Player, player_id) do
      nil -> {:error, "Player does not exist"}
      _player -> :ok
    end
  end
end
