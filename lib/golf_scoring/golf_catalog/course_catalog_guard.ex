defmodule GolfScoring.GolfCatalog.CourseCatalogGuard do
  @moduledoc false

  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    operation = Keyword.fetch!(opts, :operation)

    Ash.Changeset.before_action(changeset, &apply_operation(&1, operation))
  end

  defp apply_operation(changeset, :update_course) do
    if changeset.data.status == :archived do
      Ash.Changeset.add_error(changeset, field: :status, message: "course is archived")
    else
      changeset
    end
  end

  defp apply_operation(changeset, :archive_course) do
    case changeset.data.status do
      :archived ->
        Ash.Changeset.add_error(changeset,
          field: :status,
          message: "course is already archived"
        )

      _ ->
        Ash.Changeset.force_change_attribute(changeset, :status, :archived)
    end
  end
end
