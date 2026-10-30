defmodule GolfScoring.GolfCatalog.Validations.ReferencedCourseActiveInDatabase do
  @moduledoc false

  use Ash.Resource.Validation

  import Ash.Expr

  alias Ash.Error.Changes.InvalidAttribute
  alias GolfScoring.GolfCatalog.Course
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
        case Repo.get(Course, course_id) do
          %{status: :active} ->
            :ok

          _ ->
            {:error, field: :course_id, message: message}
        end
    end
  end

  @impl true
  def atomic(_changeset, opts, context) do
    message = Keyword.fetch!(opts, :message)

    {:atomic, [:course_id],
     expr(not exists(Course, id == ^atomic_ref(:course_id) and status == "active")),
     expr(
       error(^InvalidAttribute, %{
         field: :course_id,
         message: ^(context.message || message),
         value: ^atomic_ref(:course_id)
       })
     )}
  end
end
