defmodule GolfScoring.Competition.Services.SnapshotRoundTeeProfiles do
  @moduledoc false

  alias Decimal, as: D
  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Competition.RoundTeeHoleSnapshot
  alias GolfScoring.Competition.RoundTeeProfileSnapshot
  alias GolfScoring.Repo

  @snapshot_roles [:event_admin, :competition_manager]
  @allowed_states ~w(draft ready)
  @required_hole_count 18

  @spec run(map(), Ecto.UUID.t(), [Ecto.UUID.t()]) ::
          {:ok, [RoundTeeProfileSnapshot.t()]} | {:error, term()}
  def run(actor, round_id, tee_rating_profile_ids)
      when is_map(actor) and is_list(tee_rating_profile_ids) do
    actor_id = Map.get(actor, :id)

    Repo.transaction(fn ->
      with {:ok, round} <- fetch_round(round_id),
           {:ok, _scope} <- EventAuthorityLock.lock_scope!(round.event_id, [actor_id]),
           {:ok, round} <- lock_round(round_id),
           :ok <- authorize(actor_id, round.event_id),
           :ok <- round_accepts_snapshot(round),
           {:ok, round_holes} <- lock_round_holes(round_id),
           :ok <- validate_route_complete(round_holes),
           {:ok, profile_ids} <- validate_profile_input(tee_rating_profile_ids),
           {:ok, profiles} <- lock_catalog_profiles(profile_ids, round.course_id),
           :ok <- validate_profiles_for_route(profiles, round_holes),
           {:ok, snapshots} <- reconcile_snapshots(round, round_holes, profiles, profile_ids) do
        snapshots
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_result()
  end

  def run(_actor, _round_id, _tee_rating_profile_ids), do: {:error, :invalid_input}

  defp fetch_round(round_id) do
    case round_row(round_id) do
      nil -> {:error, :round_not_found}
      round -> {:ok, round}
    end
  end

  defp lock_round(round_id) do
    case round_row_for_update(round_id) do
      nil -> {:error, :round_not_found}
      round -> {:ok, round}
    end
  end

  defp round_row(round_id) do
    case Repo.query!(
           "SELECT id::text, event_id::text, course_id::text, state FROM rounds WHERE id = $1::uuid",
           [Ecto.UUID.dump!(round_id)]
         ).rows do
      [[id, event_id, course_id, state]] -> decode_round_row(id, event_id, course_id, state)
      [] -> nil
    end
  end

  defp round_row_for_update(round_id) do
    case Repo.query!(
           "SELECT id::text, event_id::text, course_id::text, state FROM rounds WHERE id = $1::uuid FOR UPDATE",
           [Ecto.UUID.dump!(round_id)]
         ).rows do
      [[id, event_id, course_id, state]] -> decode_round_row(id, event_id, course_id, state)
      [] -> nil
    end
  end

  defp decode_round_row(id, event_id, course_id, state) do
    %{
      id: Ecto.UUID.cast!(id),
      event_id: Ecto.UUID.cast!(event_id),
      course_id: Ecto.UUID.cast!(course_id),
      state: state
    }
  end

  defp authorize(actor_id, event_id) do
    if ActiveEventRole.authorized?(actor_id, event_id, @snapshot_roles) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp round_accepts_snapshot(%{state: state}) when state in @allowed_states, do: :ok

  defp round_accepts_snapshot(%{state: state}), do: {:error, {:invalid_round_state, state}}

  defp lock_round_holes(round_id) do
    rows =
      Repo.query!(
        """
        SELECT id::text, course_hole_id::text, play_order
        FROM round_holes
        WHERE round_id = $1::uuid
        ORDER BY play_order, id
        FOR UPDATE
        """,
        [Ecto.UUID.dump!(round_id)]
      ).rows

    holes =
      Enum.map(rows, fn [id, course_hole_id, play_order] ->
        %{
          id: Ecto.UUID.cast!(id),
          course_hole_id: Ecto.UUID.cast!(course_hole_id),
          play_order: play_order
        }
      end)

    {:ok, holes}
  end

  defp validate_route_complete(holes) when length(holes) == @required_hole_count, do: :ok
  defp validate_route_complete(_holes), do: {:error, :round_route_incomplete}

  defp validate_profile_input([]), do: {:error, :no_tee_rating_profiles}

  defp validate_profile_input(profile_ids) do
    unique = Enum.uniq(profile_ids)

    if length(unique) != length(profile_ids) do
      {:error, :duplicate_tee_rating_profile}
    else
      {:ok, Enum.sort(unique)}
    end
  end

  defp lock_catalog_profiles(profile_ids, round_course_id) do
    rows =
      Repo.query!(
        """
        SELECT
          p.id::text,
          p.tee_set_id::text,
          p.rating_label,
          p.course_rating,
          p.slope_rating,
          p.total_par,
          p.hole_ratings,
          p.updated_at,
          t.name,
          t.course_id::text,
          t.updated_at
        FROM tee_rating_profiles p
        INNER JOIN tee_sets t ON t.id = p.tee_set_id
        WHERE p.id = ANY($1::uuid[])
        ORDER BY p.id
        FOR UPDATE OF p, t
        """,
        [Enum.map(profile_ids, &Ecto.UUID.dump!/1)]
      ).rows

    if length(rows) != length(profile_ids) do
      {:error, :tee_rating_profile_not_found}
    else
      build_locked_profiles(rows, round_course_id)
    end
  end

  defp build_locked_profiles(rows, round_course_id) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case build_locked_profile(row, round_course_id) do
        {:ok, profile} -> {:cont, {:ok, [profile | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, profiles} -> {:ok, Enum.reverse(profiles)}
      error -> error
    end
  end

  defp build_locked_profile(
         [
           id,
           tee_set_id,
           rating_label,
           course_rating,
           slope_rating,
           total_par,
           hole_ratings,
           profile_updated_at,
           tee_set_name,
           course_id,
           tee_set_updated_at
         ],
         round_course_id
       ) do
    course_id = Ecto.UUID.cast!(course_id)

    if course_id != round_course_id do
      {:error, :cross_course_tee_profile}
    else
      with {:ok, ratings_by_hole} <- ratings_by_course_hole(hole_ratings) do
        {:ok,
         %{
           id: Ecto.UUID.cast!(id),
           tee_set_id: Ecto.UUID.cast!(tee_set_id),
           rating_label: rating_label,
           course_rating: course_rating,
           slope_rating: slope_rating,
           total_par: total_par,
           hole_ratings: ratings_by_hole,
           profile_updated_at: profile_updated_at,
           tee_set_name: tee_set_name,
           tee_set_updated_at: tee_set_updated_at
         }}
      end
    end
  end

  defp ratings_by_course_hole(hole_ratings) when is_list(hole_ratings) do
    normalized =
      Enum.map(hole_ratings, fn rating ->
        rating = normalize_rating_map(rating)

        %{
          course_hole_id: cast_uuid!(rating["course_hole_id"] || rating[:course_hole_id]),
          par: rating["par"] || rating[:par],
          stroke_index: rating["stroke_index"] || rating[:stroke_index],
          distance_m: rating["distance_m"] || rating[:distance_m]
        }
      end)

    grouped = Enum.group_by(normalized, & &1.course_hole_id)

    if Enum.any?(grouped, fn {_id, list} -> length(list) > 1 end) do
      {:error, :ambiguous_round_hole_rating}
    else
      {:ok, Map.new(grouped, fn {id, [rating | _]} -> {id, rating} end)}
    end
  end

  defp normalize_rating_map(%{} = map), do: map
  defp normalize_rating_map(other), do: Map.new(other)

  defp cast_uuid!(id) when is_binary(id), do: Ecto.UUID.cast!(id)
  defp cast_uuid!(id), do: id

  defp validate_profiles_for_route(profiles, round_holes) do
    Enum.reduce_while(profiles, :ok, fn profile, :ok ->
      missing =
        Enum.find(round_holes, fn hole ->
          not Map.has_key?(profile.hole_ratings, hole.course_hole_id)
        end)

      if missing do
        {:halt, {:error, :missing_round_hole_rating}}
      else
        {:cont, :ok}
      end
    end)
  end

  defp reconcile_snapshots(round, round_holes, profiles, ordered_profile_ids) do
    existing_rows =
      Repo.query!(
        """
        SELECT id::text, source_tee_rating_profile_id::text
        FROM round_tee_profile_snapshots
        WHERE round_id = $1::uuid
        ORDER BY id
        FOR UPDATE
        """,
        [Ecto.UUID.dump!(round.id)]
      ).rows

    existing_by_profile =
      Map.new(existing_rows, fn [snapshot_id, profile_id] ->
        {Ecto.UUID.cast!(profile_id), Ecto.UUID.cast!(snapshot_id)}
      end)

    profiles_by_id = Map.new(profiles, &{&1.id, &1})
    desired_set = MapSet.new(ordered_profile_ids)

    for {profile_id, snapshot_id} <- existing_by_profile,
        not MapSet.member?(desired_set, profile_id) do
      remove_hole_snapshots(snapshot_id, round.id)
      remove_profile_snapshot(snapshot_id)
    end

    snapshots =
      Enum.map(ordered_profile_ids, fn profile_id ->
        profile = Map.fetch!(profiles_by_id, profile_id)

        case Map.get(existing_by_profile, profile_id) do
          nil -> insert_profile_snapshot(round, profile, round_holes)
          snapshot_id -> refresh_profile_snapshot(round, snapshot_id, profile, round_holes)
        end
      end)

    {:ok, snapshots}
  end

  defp profile_attrs(round, profile, round_holes) do
    Map.merge(
      %{
        round_id: round.id,
        course_id: round.course_id,
        source_tee_set_id: profile.tee_set_id,
        source_tee_rating_profile_id: profile.id
      },
      refresh_profile_attrs(round, profile, round_holes)
    )
  end

  defp refresh_profile_attrs(_round, profile, round_holes) do
    applicable_par =
      round_holes
      |> Enum.map(fn hole -> Map.fetch!(profile.hole_ratings, hole.course_hole_id).par end)
      |> Enum.sum()

    %{
      tee_set_name: profile.tee_set_name,
      rating_label: profile.rating_label,
      course_rating: normalize_decimal(profile.course_rating),
      slope_rating: profile.slope_rating,
      total_par: profile.total_par,
      applicable_par: applicable_par,
      source_tee_set_updated_at: profile.tee_set_updated_at,
      source_tee_rating_profile_updated_at: profile.profile_updated_at
    }
  end

  defp insert_profile_snapshot(round, profile, round_holes) do
    snapshot =
      RoundTeeProfileSnapshot
      |> Ash.Changeset.for_create(:insert_snapshot, profile_attrs(round, profile, round_holes))
      |> Ash.create!(authorize?: false)

    Enum.each(round_holes, fn hole ->
      rating = Map.fetch!(profile.hole_ratings, hole.course_hole_id)

      RoundTeeHoleSnapshot
      |> Ash.Changeset.for_create(:insert_hole_snapshot, %{
        round_tee_profile_snapshot_id: snapshot.id,
        round_id: round.id,
        round_hole_id: hole.id,
        par: rating.par,
        stroke_index: rating.stroke_index,
        distance_m: rating.distance_m
      })
      |> Ash.create!(authorize?: false)
    end)

    snapshot
  end

  defp refresh_profile_snapshot(round, snapshot_id, profile, round_holes) do
    snapshot =
      RoundTeeProfileSnapshot
      |> Ash.get!(snapshot_id, authorize?: false)
      |> Ash.Changeset.for_update(
        :refresh_snapshot_values,
        refresh_profile_attrs(round, profile, round_holes)
      )
      |> Ash.update!(authorize?: false)

    existing_holes =
      Repo.query!(
        """
        SELECT id::text, round_hole_id::text
        FROM round_tee_hole_snapshots
        WHERE round_tee_profile_snapshot_id = $1::uuid
        ORDER BY round_hole_id
        FOR UPDATE
        """,
        [Ecto.UUID.dump!(snapshot_id)]
      ).rows
      |> Map.new(fn [id, round_hole_id] ->
        {Ecto.UUID.cast!(round_hole_id), Ecto.UUID.cast!(id)}
      end)

    Enum.each(round_holes, fn hole ->
      rating = Map.fetch!(profile.hole_ratings, hole.course_hole_id)
      hole_snapshot_id = Map.fetch!(existing_holes, hole.id)

      RoundTeeHoleSnapshot
      |> Ash.get!(hole_snapshot_id, authorize?: false)
      |> Ash.Changeset.for_update(:refresh_hole_snapshot_values, %{
        par: rating.par,
        stroke_index: rating.stroke_index,
        distance_m: rating.distance_m
      })
      |> Ash.update!(authorize?: false)
    end)

    snapshot
  end

  defp remove_hole_snapshots(snapshot_id, round_id) do
    rows =
      Repo.query!(
        """
        SELECT id::text
        FROM round_tee_hole_snapshots
        WHERE round_tee_profile_snapshot_id = $1::uuid AND round_id = $2::uuid
        ORDER BY id
        FOR UPDATE
        """,
        [Ecto.UUID.dump!(snapshot_id), Ecto.UUID.dump!(round_id)]
      ).rows

    Enum.each(rows, fn [id] ->
      RoundTeeHoleSnapshot
      |> Ash.get!(Ecto.UUID.cast!(id), authorize?: false)
      |> Ash.Changeset.for_destroy(:remove_hole_snapshot, %{})
      |> Ash.destroy!(authorize?: false)
    end)
  end

  defp remove_profile_snapshot(snapshot_id) do
    RoundTeeProfileSnapshot
    |> Ash.get!(snapshot_id, authorize?: false)
    |> Ash.Changeset.for_destroy(:remove_snapshot, %{})
    |> Ash.destroy!(authorize?: false)
  end

  defp normalize_decimal(%Decimal{} = value), do: value
  defp normalize_decimal(value), do: D.new(value)

  defp normalize_result({:ok, snapshots}) when is_list(snapshots), do: {:ok, snapshots}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result({:ok, other}), do: {:error, other}
  defp normalize_result(other), do: other
end
