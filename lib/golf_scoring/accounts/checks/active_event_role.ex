defmodule GolfScoring.Accounts.Checks.ActiveEventRole do
  @moduledoc "Checks current active Event role authority for Ash policies."

  use Ash.Policy.SimpleCheck

  alias GolfScoring.Repo

  @impl true
  def describe(_opts), do: "actor has an active Event role in the requested Event"

  @impl true
  def requires_original_data?(_authorizer, _opts), do: true

  @impl true
  def match?(actor, context, opts) do
    actor_id = if is_map(actor), do: Map.get(actor, :id), else: nil

    event_id =
      subject_event_id(Map.get(context, :subject), Map.get(context, :resource)) ||
        subject_event_id(Map.get(context, :changeset), Map.get(context, :resource))

    roles = opts[:roles] || List.wrap(opts[:role])

    authorized?(actor_id, event_id, roles)
  end

  @doc false
  def authorized?(actor_id, event_id, roles, repo \\ Repo) do
    roles = Enum.map(List.wrap(roles), &to_string/1)

    with {:ok, actor_id} <- Ecto.UUID.cast(actor_id),
         {:ok, event_id} <- Ecto.UUID.cast(event_id),
         false <- roles == [] do
      case repo.query!(
             """
             SELECT EXISTS (
               SELECT 1
               FROM staff_users staff
               JOIN event_staff_assignments assignments
                 ON assignments.staff_user_id = staff.id
               WHERE staff.id = $1::uuid
                 AND staff.status = 'active'
                 AND assignments.event_id = $2::uuid
                 AND assignments.role = ANY($3::text[])
                 AND assignments.status = 'active'
             )
             """,
             [Ecto.UUID.dump!(actor_id), Ecto.UUID.dump!(event_id), roles]
           ).rows do
        [[true]] -> true
        [[false]] -> false
      end
    else
      _ -> false
    end
  end

  defp subject_event_id(
         %Ash.Changeset{resource: GolfScoring.Competition.Event, data: %{id: event_id}},
         _context_resource
       ) do
    event_id
  end

  defp subject_event_id(%Ash.Changeset{} = changeset, _context_resource) do
    Ash.Changeset.get_argument(changeset, :event_id) ||
      Map.get(changeset.attributes, :event_id) ||
      Map.get(changeset.data, :event_id)
  end

  defp subject_event_id(%{resource: resource, data: %{id: event_id}}, _context_resource)
       when resource == GolfScoring.Competition.Event do
    event_id
  end

  defp subject_event_id(%{attributes: attributes, data: data}, _context_resource) do
    Map.get(attributes, :event_id) || Map.get(data, :event_id)
  end

  defp subject_event_id(%{event_id: event_id}, _context_resource), do: event_id

  defp subject_event_id(%{id: event_id}, GolfScoring.Competition.Event), do: event_id

  defp subject_event_id(_, _), do: nil
end
