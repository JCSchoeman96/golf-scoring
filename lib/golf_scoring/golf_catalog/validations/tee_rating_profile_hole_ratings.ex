defmodule GolfScoring.GolfCatalog.Validations.TeeRatingProfileHoleRatings do
  @moduledoc false

  use Ash.Resource.Validation

  require Ash.Query

  alias GolfScoring.GolfCatalog.CourseHole
  alias GolfScoring.GolfCatalog.TeeSet
  alias GolfScoring.Repo

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    tee_set_id = Ash.Changeset.get_attribute(changeset, :tee_set_id)
    hole_ratings = Ash.Changeset.get_attribute(changeset, :hole_ratings) || []

    with {:ok, tee_set} <- fetch_tee_set(tee_set_id),
         :ok <- validate_no_duplicate_holes(hole_ratings),
         :ok <- validate_holes_belong_to_course(hole_ratings, tee_set.course_id) do
      :ok
    end
  end

  defp fetch_tee_set(nil), do: {:error, field: :tee_set_id, message: "is required"}

  defp fetch_tee_set(tee_set_id) do
    case Repo.get(TeeSet, tee_set_id) do
      nil -> {:error, field: :tee_set_id, message: "does not reference a valid tee set"}
      tee_set -> {:ok, tee_set}
    end
  end

  defp hole_ids(hole_ratings) do
    hole_ratings
    |> Enum.map(fn
      %{course_hole_id: id} -> id
      %{} = entry -> Map.get(entry, :course_hole_id) || Map.get(entry, "course_hole_id")
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp validate_no_duplicate_holes(hole_ratings) do
    hole_ids = hole_ids(hole_ratings)

    if length(hole_ids) == length(Enum.uniq(hole_ids)) do
      :ok
    else
      {:error, field: :hole_ratings, message: "must not contain duplicate course holes"}
    end
  end

  defp validate_holes_belong_to_course(hole_ratings, course_id) do
    hole_ids = hole_ids(hole_ratings)

    if hole_ids == [] do
      :ok
    else
      matching_count =
        CourseHole
        |> Ash.Query.filter(id in ^hole_ids and course_id == ^course_id)
        |> Ash.read!(authorize?: false)
        |> length()

      if matching_count == length(hole_ids) do
        :ok
      else
        {:error,
         field: :hole_ratings, message: "must reference course holes on the tee set course"}
      end
    end
  end
end
