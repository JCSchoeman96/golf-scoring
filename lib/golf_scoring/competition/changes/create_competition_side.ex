defmodule GolfScoring.Competition.Changes.CreateCompetitionSide do
  @moduledoc false

  use Ash.Resource.Change

  alias Ash.Changeset
  alias GolfScoring.Competition.CompetitionSideResult

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, side ->
      case CompetitionSideResult
           |> Changeset.for_create(:create_provisional_internal, %{competition_side_id: side.id})
           |> Ash.create(authorize?: false) do
        {:ok, _result} -> {:ok, side}
        {:error, error} -> {:error, error}
      end
    end)
  end
end
