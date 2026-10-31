defmodule GolfScoring.Competition.Services.ConfigureRoundLayout do
  @moduledoc false

  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Competition.RoundHole
  alias GolfScoring.Repo

  @layout_roles [:event_admin, :competition_manager]
  @allowed_states ~w(draft ready)
  @required_hole_count 18

  @spec run(map(), Ecto.UUID.t(), [Ecto.UUID.t()]) ::
          {:ok, [RoundHole.t()]} | {:error, term()}
  def run(actor, round_id, course_hole_ids) when is_map(actor) and is_list(course_hole_ids) do
    actor_id = Map.get(actor, :id)

    Repo.transaction(fn ->
      with {:ok, round} <- fetch_round(round_id),
           {:ok, _scope} <- EventAuthorityLock.lock_scope!(round.event_id, [actor_id]),
           {:ok, round} <- lock_round(round_id),
           :ok <- authorize(actor_id, round.event_id),
           :ok <- round_accepts_layout(round),
           {:ok, holes_by_id} <- load_course_holes(round.course_id, course_hole_ids),
           :ok <- validate_route(course_hole_ids, round.course_id, holes_by_id),
           :ok <- validate_layout_compatible_with_snapshots(round.id, course_hole_ids),
           {:ok, route} <- apply_layout(round, course_hole_ids, holes_by_id) do
        route
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_result()
  end

  def run(_actor, _round_id, _course_hole_ids), do: {:error, :invalid_input}

  defp fetch_round(round_id) do
    case Repo.query!(
           "SELECT id::text, event_id::text, course_id::text, state FROM rounds WHERE id = $1::uuid",
           [Ecto.UUID.dump!(round_id)]
         ).rows do
      [[id, event_id, course_id, state]] ->
        {:ok,
         %{
           id: Ecto.UUID.cast!(id),
           event_id: Ecto.UUID.cast!(event_id),
           course_id: Ecto.UUID.cast!(course_id),
           state: state
         }}

      [] ->
        {:error, :round_not_found}
    end
  end

  defp lock_round(round_id) do
    case Repo.query!(
           "SELECT id::text, event_id::text, course_id::text, state FROM rounds WHERE id = $1::uuid FOR UPDATE",
           [Ecto.UUID.dump!(round_id)]
         ).rows do
      [[id, event_id, course_id, state]] ->
        {:ok,
         %{
           id: Ecto.UUID.cast!(id),
           event_id: Ecto.UUID.cast!(event_id),
           course_id: Ecto.UUID.cast!(course_id),
           state: state
         }}

      [] ->
        {:error, :round_not_found}
    end
  end

  defp authorize(actor_id, event_id) do
    if ActiveEventRole.authorized?(actor_id, event_id, @layout_roles) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp round_accepts_layout(%{state: state}) when state in @allowed_states, do: :ok

  defp round_accepts_layout(%{state: state}) do
    {:error, {:invalid_round_state, state}}
  end

  defp load_course_holes(_course_id, course_hole_ids) do
    unique_ids = Enum.uniq(course_hole_ids)

    rows =
      Repo.query!(
        """
        SELECT id::text, course_id::text, hole_number
        FROM course_holes
        WHERE id = ANY($1::uuid[])
        ORDER BY id
        FOR UPDATE
        """,
        [Enum.map(unique_ids, &Ecto.UUID.dump!/1)]
      ).rows

    holes_by_id =
      Map.new(rows, fn [id, row_course_id, hole_number] ->
        {Ecto.UUID.cast!(id),
         %{
           id: Ecto.UUID.cast!(id),
           course_id: Ecto.UUID.cast!(row_course_id),
           hole_number: hole_number
         }}
      end)

    {:ok, holes_by_id}
  end

  defp validate_route(course_hole_ids, round_course_id, holes_by_id) do
    cond do
      length(course_hole_ids) != @required_hole_count ->
        {:error, :invalid_hole_count}

      length(Enum.uniq(course_hole_ids)) != @required_hole_count ->
        {:error, :duplicate_course_hole}

      Enum.any?(course_hole_ids, fn id ->
        case Map.get(holes_by_id, id) do
          %{course_id: course_id} -> course_id != round_course_id
          _ -> true
        end
      end) ->
        {:error, :cross_course_hole}

      Enum.any?(course_hole_ids, &(not Map.has_key?(holes_by_id, &1))) ->
        {:error, :missing_course_hole}

      true ->
        :ok
    end
  end

  defp validate_layout_compatible_with_snapshots(round_id, course_hole_ids) do
    [[has_snapshots?]] =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1 FROM round_tee_profile_snapshots WHERE round_id = $1::uuid
        )
        """,
        [Ecto.UUID.dump!(round_id)]
      ).rows

    if has_snapshots? do
      current_ids =
        Repo.query!(
          "SELECT course_hole_id::text FROM round_holes WHERE round_id = $1::uuid ORDER BY play_order",
          [Ecto.UUID.dump!(round_id)]
        ).rows
        |> Enum.map(fn [id] -> Ecto.UUID.cast!(id) end)

      if MapSet.new(current_ids) == MapSet.new(course_hole_ids) do
        :ok
      else
        {:error, :round_snapshots_block_route_change}
      end
    else
      :ok
    end
  end

  defp apply_layout(round, course_hole_ids, holes_by_id) do
    existing =
      Repo.query!(
        """
        SELECT id::text, course_hole_id::text, play_order
        FROM round_holes
        WHERE round_id = $1::uuid
        ORDER BY play_order, id
        FOR UPDATE
        """,
        [Ecto.UUID.dump!(round.id)]
      ).rows
      |> Enum.map(fn [id, course_hole_id, play_order] ->
        %{
          id: Ecto.UUID.cast!(id),
          course_hole_id: Ecto.UUID.cast!(course_hole_id),
          play_order: play_order
        }
      end)

    existing_by_course_hole = Map.new(existing, &{&1.course_hole_id, &1})
    desired_set = MapSet.new(course_hole_ids)

    for row <- existing, row.course_hole_id not in desired_set do
      RoundHole
      |> Ash.get!(row.id, authorize?: false)
      |> Ash.Changeset.for_destroy(:remove_layout_row, %{})
      |> Ash.destroy!(authorize?: false)
    end

    retained =
      Enum.filter(existing, fn row -> row.course_hole_id in desired_set end)

    Enum.with_index(retained, 1)
    |> Enum.each(fn {row, index} ->
      RoundHole
      |> Ash.get!(row.id, authorize?: false)
      |> Ash.Changeset.for_update(:update_layout_row, %{play_order: 1000 + index})
      |> Ash.update!(authorize?: false)
    end)

    route_rows =
      Enum.with_index(course_hole_ids, 1)
      |> Enum.map(fn {course_hole_id, play_order} ->
        hole = Map.fetch!(holes_by_id, course_hole_id)
        display = hole.hole_number

        case Map.get(existing_by_course_hole, course_hole_id) do
          %{id: id} ->
            RoundHole
            |> Ash.get!(id, authorize?: false)
            |> Ash.Changeset.for_update(:update_layout_row, %{
              play_order: play_order,
              display_hole_number: display
            })
            |> Ash.update!(authorize?: false)

          nil ->
            RoundHole
            |> Ash.Changeset.for_create(:insert_layout_row, %{
              round_id: round.id,
              course_hole_id: course_hole_id,
              course_id: round.course_id,
              play_order: play_order,
              display_hole_number: display
            })
            |> Ash.create!(authorize?: false)
        end
      end)

    {:ok, route_rows}
  end

  defp normalize_result({:ok, route}) when is_list(route), do: {:ok, route}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result({:ok, other}), do: {:error, other}
  defp normalize_result(other), do: other
end
