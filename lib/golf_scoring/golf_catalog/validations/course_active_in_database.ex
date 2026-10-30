defmodule GolfScoring.GolfCatalog.Validations.CourseActiveInDatabase do
  @moduledoc false

  use Ash.Resource.Validation

  import Ash.Expr

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def init(opts) do
    {:ok, Keyword.put_new(opts, :message, "course is archived")}
  end

  @impl true
  def validate(_changeset, _opts, _context), do: :ok

  @impl true
  def atomic(_changeset, opts, context) do
    message = Keyword.fetch!(opts, :message)

    {:atomic, [:status], expr(^atomic_ref(:status) != "active"),
     expr(
       error(^InvalidAttribute, %{
         field: :status,
         message: ^(context.message || message),
         value: ^atomic_ref(:status)
       })
     )}
  end
end
