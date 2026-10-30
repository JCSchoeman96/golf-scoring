defmodule GolfScoring.GolfCatalog.Changes.ValidateTeeRatingProfileHoleRatings do
  @moduledoc false

  use Ash.Resource.Change

  alias GolfScoring.GolfCatalog.Validations.TeeRatingProfileHoleRatings

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case TeeRatingProfileHoleRatings.validate(changeset, opts, %{}) do
        :ok ->
          changeset

        {:error, field: field, message: message} ->
          Ash.Changeset.add_error(changeset, field: field, message: message)
      end
    end)
  end
end
