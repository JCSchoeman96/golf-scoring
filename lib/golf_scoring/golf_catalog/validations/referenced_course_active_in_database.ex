defmodule GolfScoring.GolfCatalog.Validations.ReferencedCourseActiveInDatabase do
  @moduledoc false

  use Ash.Resource.Validation

  alias GolfScoring.Repo

  @impl true
  def init(opts) do
    {:ok, Keyword.put_new(opts, :message, "course is archived")}
  end

  @impl true
  def validate(changeset, opts, _context) do
    message = Keyword.fetch!(opts, :message)

    case Ash.Changeset.get_attribute(changeset, :course_id) do
      nil ->
        :ok

      course_id ->
        case lock_and_verify_active(course_id) do
          :ok -> :ok
          :error -> {:error, field: :course_id, message: message}
        end
    end
  end

  defp lock_and_verify_active(course_id) do
    case Repo.query!(
           "SELECT status FROM courses WHERE id = $1::uuid FOR SHARE",
           [Ecto.UUID.dump!(course_id)]
         ) do
      %{rows: [["active"]]} -> :ok
      _ -> :error
    end
  end
end
