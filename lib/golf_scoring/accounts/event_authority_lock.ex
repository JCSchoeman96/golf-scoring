defmodule GolfScoring.Accounts.EventAuthorityLock do
  @moduledoc false

  alias GolfScoring.Repo

  def lock_scope!(event_id, staff_user_ids, assignment_ids \\ []) do
    unless Repo.in_transaction?() do
      raise ArgumentError, "Event authority locks require an open repository transaction"
    end

    with {:ok, event} <- lock_event(event_id) do
      admin_staff_ids = active_event_admin_staff_ids(event_id)
      staff_ids = ordered_ids(staff_user_ids ++ admin_staff_ids)
      locked_staff_users = lock_staff_users(staff_ids)
      assignments = lock_assignments(event_id, staff_ids, assignment_ids)

      {:ok,
       %{
         event: event,
         staff_users: locked_staff_users,
         assignments: assignments
       }}
    end
  end

  def effective_event_admin_count(scope) do
    Enum.count(scope.assignments, fn assignment ->
      staff_user = Map.get(scope.staff_users, assignment.staff_user_id)

      assignment.role == "event_admin" and assignment.status == "active" and
        match?(%{status: "active"}, staff_user)
    end)
  end

  def assignment(scope, assignment_id) do
    Enum.find(scope.assignments, &(&1.id == assignment_id))
  end

  def staff_user(scope, staff_user_id) do
    Map.get(scope.staff_users, staff_user_id)
  end

  defp lock_event(event_id) do
    case Repo.query!(
           "SELECT id::text, state FROM events WHERE id = $1::uuid FOR UPDATE",
           [Ecto.UUID.dump!(event_id)]
         ).rows do
      [[id, state]] -> {:ok, %{id: Ecto.UUID.cast!(id), state: state}}
      [] -> {:error, "Event does not exist"}
    end
  end

  defp active_event_admin_staff_ids(event_id) do
    Repo.query!(
      "SELECT staff_user_id::text FROM event_staff_assignments WHERE event_id = $1::uuid AND role = 'event_admin' AND status = 'active'",
      [Ecto.UUID.dump!(event_id)]
    ).rows
    |> Enum.map(fn [staff_user_id] -> Ecto.UUID.cast!(staff_user_id) end)
  end

  defp lock_staff_users(staff_user_ids) do
    Repo.query!(
      "SELECT id::text, status FROM staff_users WHERE id = ANY($1::uuid[]) ORDER BY id FOR UPDATE",
      [Enum.map(staff_user_ids, &Ecto.UUID.dump!/1)]
    ).rows
    |> Map.new(fn [id, status] -> {Ecto.UUID.cast!(id), %{status: status}} end)
  end

  defp lock_assignments(event_id, staff_user_ids, assignment_ids) do
    staff_user_ids = Enum.map(staff_user_ids, &Ecto.UUID.dump!/1)
    assignment_ids = assignment_ids |> ordered_ids() |> Enum.map(&Ecto.UUID.dump!/1)

    Repo.query!(
      """
      SELECT id::text, staff_user_id::text, role, status
      FROM event_staff_assignments
      WHERE event_id = $1::uuid
        AND (staff_user_id = ANY($2::uuid[]) OR id = ANY($3::uuid[]))
      ORDER BY id
      FOR UPDATE
      """,
      [Ecto.UUID.dump!(event_id), staff_user_ids, assignment_ids]
    ).rows
    |> Enum.map(fn [id, staff_user_id, role, status] ->
      %{
        id: Ecto.UUID.cast!(id),
        staff_user_id: Ecto.UUID.cast!(staff_user_id),
        role: role,
        status: status
      }
    end)
  end

  defp ordered_ids(ids) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort_by(&Ecto.UUID.dump!/1)
  end
end
