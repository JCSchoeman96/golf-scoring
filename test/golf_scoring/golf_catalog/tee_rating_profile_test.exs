defmodule GolfScoring.GolfCatalog.TeeRatingProfileTest do
  use ExUnit.Case, async: false

  alias Ash.Resource.Info
  alias Decimal, as: D
  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Accounts.EventStaffAssignment
  alias GolfScoring.Competition.Event
  alias GolfScoring.GolfCatalog
  alias GolfScoring.GolfCatalog.Course
  alias GolfScoring.GolfCatalog.TeeRatingProfile
  alias GolfScoring.GolfCatalog.TeeSet
  alias GolfScoring.Repo

  @password "GLS-11 synthetic staff passphrase 2026"
  @duplicate_profile_constraint "tee_rating_profiles_unique_rating_context_per_tee_set_index"
  @orphan_tee_set_fkey "tee_rating_profiles_tee_set_id_fkey"

  setup tags do
    Process.put(:gls11_email_prefix, "gls11-#{Ecto.UUID.generate()}")
    on_exit(fn -> Process.delete(:gls11_email_prefix) end)

    if tags[:real_concurrency] do
      :ok = Sandbox.mode(Repo, :auto)
      on_exit(fn -> Sandbox.mode(Repo, :manual) end)
    else
      owner = Sandbox.start_owner!(Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(owner) end)
    end

    :ok
  end

  test "GolfCatalog registers TeeSet and TeeRatingProfile with named actions only" do
    assert TeeSet in Ash.Domain.Info.resources(GolfCatalog)
    assert TeeRatingProfile in Ash.Domain.Info.resources(GolfCatalog)

    assert Info.action(TeeSet, :configure_tee_set)
    assert Info.action(TeeRatingProfile, :configure_tee_rating_profile)

    assert is_nil(Info.action(TeeSet, :create))
    assert is_nil(Info.action(TeeSet, :update))
    assert is_nil(Info.action(TeeSet, :destroy))
    assert is_nil(Info.action(TeeRatingProfile, :create))
    assert is_nil(Info.action(TeeRatingProfile, :update))
    assert is_nil(Info.action(TeeRatingProfile, :destroy))
  end

  test "active EventAdmin can configure TeeSet physical identity on an active Course" do
    event = create_event!()
    admin = create_event_admin!(event)

    {:ok, course} =
      GolfCatalog.create_course(event.id, %{name: "Royal Example", location: "ZA"}, actor: admin)

    assert {:ok, tee_set} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "White"},
               actor: admin
             )

    assert tee_set.course_id == course.id
    assert tee_set.name == "White"

    assert {:ok, same} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "White"},
               actor: admin
             )

    assert same.id == tee_set.id
  end

  test "configure_tee_set on an active Course may complete before a later archive" do
    event = create_event!()
    admin = create_event_admin!(event)

    {:ok, course} =
      GolfCatalog.create_course(event.id, %{name: "Live Then Archive", location: "ZA"},
        actor: admin
      )

    assert {:ok, tee_set} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "Gold"},
               actor: admin
             )

    assert {:ok, archived} = GolfCatalog.archive_course(course, event.id, actor: admin)
    assert archived.status == :archived
    assert Repo.get!(TeeSet, tee_set.id).name == "Gold"
  end

  @tag :real_concurrency
  test "concurrent Course archival is rechecked before configure_tee_set commits" do
    event = create_event!()
    admin = create_event_admin!(event)

    {:ok, course} =
      GolfCatalog.create_course(event.id, %{name: "Race Course", location: "ZA"}, actor: admin)

    blocker = start_course_archive_blocker(course.id)
    archive_backend_pid = await_blocker!(blocker, :gls11_course_archive_locked)

    try do
      task =
        start_independent_operation(:gls11_configure_tee_set_race, fn ->
          GolfCatalog.configure_tee_set(
            event.id,
            %{course_id: course.id, name: "Blue"},
            actor: admin
          )
        end)

      [reported_configure_backend_pid] = await_operation_pids([:gls11_configure_tee_set_race])

      configure_backend_pid =
        await_configure_blocked_by_archive!(
          archive_backend_pid,
          reported_configure_backend_pid
        )

      refute archive_backend_pid == configure_backend_pid

      await_pg_blocking!(configure_backend_pid, archive_backend_pid)

      assert_configure_backend_waiting_on_lock!(configure_backend_pid)

      send(blocker.pid, :release_gls11_course_archive)
      assert {:ok, :released} = Task.await(blocker, 10_000)
      assert {:error, _error} = Task.await(task, 10_000)

      assert Repo.get!(Course, course.id).status == :archived

      assert Repo.query!(
               "SELECT 1 FROM tee_sets WHERE course_id = $1::uuid AND name = 'Blue'",
               [Ecto.UUID.dump!(course.id)]
             ).rows == []
    after
      release_course_blocker(blocker)
      cleanup_committed_catalog_fixture(event.id, course.id, admin.id)
    end
  end

  test "archived Course rejects configure_tee_set using durable database state" do
    event = create_event!()
    admin = create_event_admin!(event)

    {:ok, course} =
      GolfCatalog.create_course(event.id, %{name: "Archived Links", location: "ZA"}, actor: admin)

    assert {:ok, archived} = GolfCatalog.archive_course(course, event.id, actor: admin)

    assert {:error, _error} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: archived.id, name: "Blue"},
               actor: admin
             )
  end

  test "TeeSet schema retains only physical tee identity fields" do
    attribute_names =
      TeeSet
      |> Info.attributes()
      |> Enum.map(& &1.name)
      |> Enum.map(&Atom.to_string/1)

    refute "course_rating" in attribute_names
    refute "slope_rating" in attribute_names
    refute "total_par" in attribute_names
    refute "gender" in attribute_names

    assert Enum.sort(attribute_names) ==
             Enum.sort(~w(id course_id name inserted_at updated_at))
  end

  test "active EventAdmin can configure TeeRatingProfile rating facts" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, holes} = course_with_tee_and_holes!(event, admin, hole_numbers: [1, 2, 3])

    hole_ratings =
      Enum.map(holes, fn hole ->
        %{
          course_hole_id: hole.id,
          par: 4,
          stroke_index: hole.hole_number,
          distance_m: 350 + hole.hole_number
        }
      end)

    assert {:ok, profile} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               %{
                 tee_set_id: tee_set.id,
                 rating_label: "Standard",
                 course_rating: D.new("72.4"),
                 slope_rating: 130,
                 total_par: 12,
                 hole_ratings: hole_ratings
               },
               actor: admin
             )

    assert profile.rating_label == "Standard"
    assert D.equal?(profile.course_rating, D.new("72.4"))
    assert profile.slope_rating == 130
    assert profile.total_par == 12
    assert length(profile.hole_ratings) == 3
    assert hd(profile.hole_ratings).distance_m == 351
  end

  test "two rating profiles on the same TeeSet persist independent rating facts" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, holes} = course_with_tee_and_holes!(event, admin, hole_numbers: [1, 2])

    base_hole = fn hole, par, si, distance_m ->
      %{
        course_hole_id: hole.id,
        par: par,
        stroke_index: si,
        distance_m: distance_m
      }
    end

    [hole_1, hole_2] = holes

    assert {:ok, profile_a} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               %{
                 tee_set_id: tee_set.id,
                 rating_label: "Context A",
                 course_rating: D.new("71.0"),
                 slope_rating: 125,
                 total_par: 8,
                 hole_ratings: [
                   base_hole.(hole_1, 4, 1, 350),
                   base_hole.(hole_2, 4, 2, 360)
                 ]
               },
               actor: admin
             )

    assert {:ok, profile_b} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               %{
                 tee_set_id: tee_set.id,
                 rating_label: "Context B",
                 course_rating: D.new("73.2"),
                 slope_rating: 138,
                 total_par: 9,
                 hole_ratings: [
                   base_hole.(hole_1, 5, 2, 380),
                   base_hole.(hole_2, 4, 1, 340)
                 ]
               },
               actor: admin
             )

    assert profile_a.id != profile_b.id
    assert D.equal?(profile_a.course_rating, D.new("71.0"))
    assert D.equal?(profile_b.course_rating, D.new("73.2"))
    assert hd(profile_a.hole_ratings).par == 4
    assert hd(profile_b.hole_ratings).par == 5
  end

  test "mixed-tee catalog holds independent TeeSets and rating profiles" do
    event = create_event!()
    admin = create_event_admin!(event)

    {:ok, course} =
      GolfCatalog.create_course(event.id, %{name: "Mixed Layout", location: "ZA"}, actor: admin)

    {:ok, white} =
      GolfCatalog.configure_tee_set(event.id, %{course_id: course.id, name: "White"},
        actor: admin
      )

    {:ok, blue} =
      GolfCatalog.configure_tee_set(event.id, %{course_id: course.id, name: "Blue"}, actor: admin)

    {:ok, hole} =
      GolfCatalog.configure_course_hole(
        event.id,
        %{course_id: course.id, hole_number: 1},
        actor: admin
      )

    assert {:ok, white_profile} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               profile_params(white.id, "White Standard", "70.1", 120, 4, hole),
               actor: admin
             )

    assert {:ok, blue_profile} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               profile_params(blue.id, "Blue Standard", "72.8", 135, 4, hole),
               actor: admin
             )

    assert white_profile.tee_set_id == white.id
    assert blue_profile.tee_set_id == blue.id
    assert white_profile.id != blue_profile.id
  end

  test "duplicate rating profile identity for the same TeeSet is rejected at PostgreSQL" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, [hole | _]} = course_with_tee_and_holes!(event, admin, hole_numbers: [1])

    assert {:ok, _} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               profile_params(tee_set.id, "Duplicate Me", "71.0", 125, 4, hole),
               actor: admin
             )

    duplicate_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO tee_rating_profiles
            (tee_set_id, rating_label, course_rating, slope_rating, total_par)
          VALUES ($1::uuid, 'Duplicate Me', 71.0, 125, 4)
          """,
          [Ecto.UUID.dump!(tee_set.id)]
        )
      end

    assert duplicate_error.postgres.code == :unique_violation
    assert duplicate_error.postgres.constraint == @duplicate_profile_constraint
  end

  test "malformed duplicate-profile SQL does not prove the unique index constraint" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, [hole | _]} = course_with_tee_and_holes!(event, admin, hole_numbers: [1])

    assert {:ok, _} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               profile_params(tee_set.id, "Duplicate Me", "71.0", 125, 4, hole),
               actor: admin
             )

    malformed_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO tee_rating_profiles
            (tee_set_id, rating_label, course_rating, slope_rating, total_par, hole_ratings)
          VALUES ($1::uuid, 'Duplicate Me', 71.0, 125, 4, '[]'::jsonb)
          """,
          [Ecto.UUID.dump!(tee_set.id)]
        )
      end

    refute malformed_error.postgres.code == :unique_violation and
             malformed_error.postgres.constraint == @duplicate_profile_constraint
  end

  test "PostgreSQL rejects TeeSet rows referencing a nonexistent Course" do
    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "INSERT INTO tee_sets (course_id, name) VALUES ($1::uuid, 'Ghost')",
        [Ecto.UUID.dump!(Ecto.UUID.generate())]
      )
    end
  end

  test "PostgreSQL rejects TeeRatingProfile rows referencing a nonexistent TeeSet" do
    orphan_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO tee_rating_profiles
            (tee_set_id, rating_label, course_rating, slope_rating, total_par)
          VALUES ($1::uuid, 'Orphan', 70.0, 120, 72)
          """,
          [Ecto.UUID.dump!(Ecto.UUID.generate())]
        )
      end

    assert orphan_error.postgres.code == :foreign_key_violation
    assert orphan_error.postgres.constraint == @orphan_tee_set_fkey
  end

  test "configure_tee_rating_profile rejects CourseHole from another Course" do
    event = create_event!()
    admin = create_event_admin!(event)

    {:ok, course_a} =
      GolfCatalog.create_course(event.id, %{name: "Course A", location: "A"}, actor: admin)

    {:ok, course_b} =
      GolfCatalog.create_course(event.id, %{name: "Course B", location: "B"}, actor: admin)

    {:ok, tee_set_a} =
      GolfCatalog.configure_tee_set(event.id, %{course_id: course_a.id, name: "White"},
        actor: admin
      )

    {:ok, hole_b} =
      GolfCatalog.configure_course_hole(
        event.id,
        %{course_id: course_b.id, hole_number: 1},
        actor: admin
      )

    assert {:error, _error} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               %{
                 tee_set_id: tee_set_a.id,
                 rating_label: "Cross Course",
                 course_rating: D.new("71.0"),
                 slope_rating: 125,
                 total_par: 4,
                 hole_ratings: [
                   %{course_hole_id: hole_b.id, par: 4, stroke_index: 1, distance_m: 350}
                 ]
               },
               actor: admin
             )
  end

  test "configure_tee_rating_profile rejects duplicate hole entries in one profile" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, [hole | _]} = course_with_tee_and_holes!(event, admin, hole_numbers: [1])

    assert {:error, _error} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               %{
                 tee_set_id: tee_set.id,
                 rating_label: "Dup Holes",
                 course_rating: D.new("71.0"),
                 slope_rating: 125,
                 total_par: 8,
                 hole_ratings: [
                   %{course_hole_id: hole.id, par: 4, stroke_index: 1, distance_m: 350},
                   %{course_hole_id: hole.id, par: 5, stroke_index: 2, distance_m: 360}
                 ]
               },
               actor: admin
             )
  end

  test "GLS-73 tee rating profile accepts absent plus stroke allocation" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, holes} = course_with_tee_and_holes!(event, admin, hole_numbers: 1..18)

    hole_ratings =
      Enum.map(holes, fn hole ->
        %{course_hole_id: hole.id, par: 4, stroke_index: hole.hole_number, distance_m: 350}
      end)

    assert {:ok, profile} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               profile_params_for_holes(tee_set.id, "Men", holes, hole_ratings),
               actor: admin
             )

    assert Enum.all?(profile.hole_ratings, fn rating -> is_nil(rating.plus_stroke_order) end)
  end

  test "GLS-73 complete plus stroke allocation 1..8 persists through reload" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, holes} = course_with_tee_and_holes!(event, admin, hole_numbers: 1..18)

    hole_ratings = hole_ratings_with_plus_orders(holes)

    assert {:ok, profile} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               profile_params_for_holes(tee_set.id, "Men", holes, hole_ratings),
               actor: admin
             )

    reloaded = Repo.get!(TeeRatingProfile, profile.id)

    assert plus_orders_by_hole_number(reloaded.hole_ratings, holes) ==
             Map.new(1..8, &{&1, &1})
  end

  test "GLS-73 rejects duplicate plus stroke orders" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, holes} = course_with_tee_and_holes!(event, admin, hole_numbers: 1..18)

    hole_ratings =
      hole_ratings_with_plus_orders(holes)
      |> List.update_at(7, fn rating -> Map.put(rating, :plus_stroke_order, 7) end)

    assert {:error, error} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               profile_params_for_holes(tee_set.id, "Men", holes, hole_ratings),
               actor: admin
             )

    assert plus_stroke_validation_error?(error)
  end

  test "GLS-73 rejects partial plus stroke allocation" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, holes} = course_with_tee_and_holes!(event, admin, hole_numbers: 1..18)

    for hole_ratings <- [
          partial_plus_orders(holes, 1..3),
          partial_plus_orders(holes, 1..7)
        ] do
      assert {:error, error} =
               GolfCatalog.configure_tee_rating_profile(
                 event.id,
                 profile_params_for_holes(tee_set.id, "Men", holes, hole_ratings),
                 actor: admin
               )

      assert plus_stroke_validation_error?(error)
    end
  end

  test "GLS-73 rejects gap in plus stroke allocation" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, holes} = course_with_tee_and_holes!(event, admin, hole_numbers: 1..18)

    hole_ratings =
      hole_ratings_with_plus_orders(holes)
      |> Enum.map(fn
        %{plus_stroke_order: 8} = rating -> Map.put(rating, :plus_stroke_order, nil)
        rating -> rating
      end)

    assert {:error, error} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               profile_params_for_holes(tee_set.id, "Men", holes, hole_ratings),
               actor: admin
             )

    assert plus_stroke_validation_error?(error)
  end

  test "GLS-73 rejects out-of-range plus stroke order values" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, holes} = course_with_tee_and_holes!(event, admin, hole_numbers: 1..18)

    for invalid <- [0, 9] do
      hole_ratings =
        hole_ratings_with_plus_orders(holes)
        |> List.update_at(0, fn rating -> Map.put(rating, :plus_stroke_order, invalid) end)

      assert {:error, _error} =
               GolfCatalog.configure_tee_rating_profile(
                 event.id,
                 profile_params_for_holes(tee_set.id, "Men", holes, hole_ratings),
                 actor: admin
               )
    end
  end

  test "wrong-event, revoked, suspended, disabled, stale actor, and SYSTEM_ADMIN-only fail closed" do
    event = create_event!()
    other_event = create_event!()
    admin = create_event_admin!(event)
    cross_event_admin = create_event_admin!(other_event)

    {:ok, course} =
      GolfCatalog.create_course(event.id, %{name: "Protected", location: "ZA"}, actor: admin)

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "Blocked"},
               actor: cross_event_admin
             )

    revoked_staff = create_event_admin!(event)

    assert {:ok, revoked} =
             Accounts.revoke_event_staff_role(
               active_assignment_record(event, revoked_staff),
               actor: admin
             )

    assert revoked.status == :revoked

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "Revoked"},
               actor: revoked_staff
             )

    system_admin = create_system_admin!()

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "System Only"},
               actor: system_admin
             )

    suspended_admin = create_event_admin!(event)
    stale_suspended = set_staff_status!(suspended_admin, :suspended)

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "Suspended"},
               actor: stale_suspended
             )

    disabled_admin = create_event_admin!(event)
    stale_disabled = set_staff_status!(disabled_admin, :disabled)

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "Disabled"},
               actor: stale_disabled
             )

    stale_active_struct = admin
    replacement = create_event_admin!(event)

    assert {:ok, _} =
             Accounts.revoke_event_staff_role(
               active_assignment_record(event, admin),
               actor: replacement
             )

    assert stale_active_struct.status == :active

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "Stale Assignment"},
               actor: stale_active_struct
             )
  end

  test "PostgreSQL preserves catalog history with restrict foreign keys on tee catalog tables" do
    event = create_event!()
    admin = create_event_admin!(event)
    {course, tee_set, [hole | _]} = course_with_tee_and_holes!(event, admin, hole_numbers: [1])

    assert {:ok, _profile} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               profile_params(tee_set.id, "Protected", "71.0", 125, 4, hole),
               actor: admin
             )

    assert_raise Postgrex.Error, fn ->
      Repo.query!("DELETE FROM courses WHERE id = $1::uuid", [Ecto.UUID.dump!(course.id)])
    end

    assert_raise Postgrex.Error, fn ->
      Repo.query!("DELETE FROM tee_sets WHERE id = $1::uuid", [Ecto.UUID.dump!(tee_set.id)])
    end
  end

  defp profile_params(tee_set_id, label, course_rating, slope_rating, total_par, hole) do
    %{
      tee_set_id: tee_set_id,
      rating_label: label,
      course_rating: D.new(course_rating),
      slope_rating: slope_rating,
      total_par: total_par,
      hole_ratings: [
        %{course_hole_id: hole.id, par: 4, stroke_index: 1, distance_m: 350}
      ]
    }
  end

  defp profile_params_for_holes(tee_set_id, label, holes, hole_ratings) do
    %{
      tee_set_id: tee_set_id,
      rating_label: label,
      course_rating: D.new("72.0"),
      slope_rating: 113,
      total_par: length(holes) * 4,
      hole_ratings: hole_ratings
    }
  end

  defp hole_ratings_with_plus_orders(holes) do
    Enum.map(holes, fn hole ->
      base = %{
        course_hole_id: hole.id,
        par: 4,
        stroke_index: hole.hole_number,
        distance_m: 350
      }

      if hole.hole_number <= 8 do
        Map.put(base, :plus_stroke_order, hole.hole_number)
      else
        base
      end
    end)
  end

  defp partial_plus_orders(holes, order_range) do
    orders = MapSet.new(order_range)

    Enum.map(holes, fn hole ->
      base = %{
        course_hole_id: hole.id,
        par: 4,
        stroke_index: hole.hole_number,
        distance_m: 350
      }

      if MapSet.member?(orders, hole.hole_number) do
        Map.put(base, :plus_stroke_order, hole.hole_number)
      else
        base
      end
    end)
  end

  defp plus_orders_by_hole_number(hole_ratings, holes) do
    hole_number_by_id = Map.new(holes, &{&1.id, &1.hole_number})

    hole_ratings
    |> Enum.filter(fn rating -> not is_nil(rating.plus_stroke_order) end)
    |> Map.new(fn rating ->
      {Map.fetch!(hole_number_by_id, rating.course_hole_id), rating.plus_stroke_order}
    end)
  end

  defp plus_stroke_validation_error?(error) do
    errors = Ash.Error.to_error_class(error).errors

    Enum.any?(errors, fn
      %{field: :hole_ratings, message: message} when is_binary(message) ->
        String.contains?(message, "Plus Strokes")

      _ ->
        false
    end)
  end

  defp course_with_tee_and_holes!(event, admin, opts) do
    hole_numbers = Keyword.fetch!(opts, :hole_numbers)

    {:ok, course} =
      GolfCatalog.create_course(
        event.id,
        %{name: "Course #{System.unique_integer([:positive])}", location: "ZA"},
        actor: admin
      )

    {:ok, tee_set} =
      GolfCatalog.configure_tee_set(
        event.id,
        %{course_id: course.id, name: "White"},
        actor: admin
      )

    holes =
      Enum.map(hole_numbers, fn hole_number ->
        {:ok, hole} =
          GolfCatalog.configure_course_hole(
            event.id,
            %{course_id: course.id, hole_number: hole_number},
            actor: admin
          )

        hole
      end)

    {course, tee_set, holes}
  end

  defp create_event! do
    Event
    |> Ash.Changeset.for_create(:create_internal, %{})
    |> Ash.create!(authorize?: false)
  end

  defp create_event_admin!(event) do
    staff = create_staff_user!()

    Repo.query!(
      "INSERT INTO event_staff_assignments (event_id, staff_user_id, role, status) VALUES ($1::uuid, $2::uuid, 'event_admin', 'active')",
      [Ecto.UUID.dump!(event.id), Ecto.UUID.dump!(staff.id)]
    )

    staff
  end

  defp active_assignment_record(event, staff) do
    [[assignment_id]] =
      Repo.query!(
        "SELECT id::text FROM event_staff_assignments WHERE event_id = $1::uuid AND staff_user_id = $2::uuid AND role = 'event_admin' AND status = 'active'",
        [Ecto.UUID.dump!(event.id), Ecto.UUID.dump!(staff.id)]
      ).rows

    EventStaffAssignment
    |> Ash.get!(assignment_id, authorize?: false)
  end

  defp create_staff_user! do
    email =
      "#{Process.get(:gls11_email_prefix)}-#{System.unique_integer([:positive])}@example.com"

    GolfScoring.Accounts.StaffUser
    |> Ash.Changeset.for_create(:provision_staff_user, %{
      email: email,
      password: @password,
      password_confirmation: @password
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_system_admin! do
    staff = create_staff_user!()

    Repo.query!("UPDATE staff_users SET system_admin = TRUE WHERE id = $1::uuid", [
      Ecto.UUID.dump!(staff.id)
    ])

    Repo.get!(GolfScoring.Accounts.StaffUser, staff.id)
  end

  defp set_staff_status!(staff, status) do
    Repo.query!("UPDATE staff_users SET status = $1 WHERE id = $2::uuid", [
      Atom.to_string(status),
      Ecto.UUID.dump!(staff.id)
    ])

    Repo.get!(GolfScoring.Accounts.StaffUser, staff.id)
  end

  defp start_course_archive_blocker(course_id) do
    parent = self()
    Task.async(fn -> hold_course_archive_lock(parent, course_id) end)
  end

  defp hold_course_archive_lock(parent, course_id) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.transaction(fn ->
        Repo.query!("SELECT id FROM courses WHERE id = $1::uuid FOR UPDATE", [
          Ecto.UUID.dump!(course_id)
        ])

        Repo.query!("UPDATE courses SET status = 'archived' WHERE id = $1::uuid", [
          Ecto.UUID.dump!(course_id)
        ])

        send(parent, {:gls11_course_archive_locked, database_backend_pid()})

        receive do
          :release_gls11_course_archive -> :released
        after
          15_000 -> Repo.rollback(:course_archive_blocker_timeout)
        end
      end)
    end)
  end

  defp start_independent_operation(tag, operation) do
    parent = self()

    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        send(parent, {tag, database_backend_pid()})
        operation.()
      end)
    end)
  end

  defp await_configure_blocked_by_archive!(archive_backend_pid, reported_configure_backend_pid) do
    deadline = System.monotonic_time(:millisecond) + 5_000

    do_await_configure_blocked_by_archive!(
      archive_backend_pid,
      reported_configure_backend_pid,
      deadline
    )
  end

  defp do_await_configure_blocked_by_archive!(
         archive_backend_pid,
         reported_configure_backend_pid,
         deadline
       ) do
    blocked_pids = pids_blocked_by(archive_backend_pid)

    configure_backend_pid =
      cond do
        reported_configure_backend_pid in blocked_pids ->
          reported_configure_backend_pid

        blocked_pids != [] ->
          hd(blocked_pids)

        true ->
          nil
      end

    if configure_backend_pid &&
         archive_backend_pid in pg_blocking_pids(configure_backend_pid) do
      configure_backend_pid
    else
      if System.monotonic_time(:millisecond) >= deadline do
        activity = pg_stat_activity(reported_configure_backend_pid)

        flunk(
          "expected archive backend #{archive_backend_pid} to block configure, blocked_pids=#{inspect(blocked_pids)}, reported_configure_backend_pid=#{reported_configure_backend_pid}, activity=#{inspect(activity)}"
        )
      else
        Process.sleep(10)

        do_await_configure_blocked_by_archive!(
          archive_backend_pid,
          reported_configure_backend_pid,
          deadline
        )
      end
    end
  end

  defp pids_blocked_by(blocker_pid) do
    Sandbox.unboxed_run(Repo, fn ->
      blocker_pid
      |> pids_blocked_by_query()
      |> map_activity_pids()
    end)
  end

  defp pids_blocked_by_query(blocker_pid) do
    Repo.query!(
      """
      SELECT pid
      FROM pg_stat_activity
      WHERE datname = current_database()
        AND pid IS NOT NULL
        AND pid <> $1::int
        AND $1::int = ANY(pg_blocking_pids(pid))
      ORDER BY pid
      """,
      [blocker_pid]
    ).rows
  end

  defp map_activity_pids(rows) when is_list(rows), do: Enum.map(rows, fn [pid] -> pid end)
  defp map_activity_pids(_), do: []

  defp await_blocker!(blocker, tag) do
    assert_receive {^tag, backend_pid}, 5_000
    assert blocker.pid != self()
    backend_pid
  end

  defp await_operation_pids(tags) do
    Enum.map(tags, fn tag ->
      assert_receive {^tag, backend_pid}, 5_000
      backend_pid
    end)
  end

  defp await_pg_blocking!(blocked_pid, expected_blocker_pid, timeout_ms \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_pg_blocking!(blocked_pid, expected_blocker_pid, deadline)
  end

  defp do_await_pg_blocking!(blocked_pid, expected_blocker_pid, deadline) do
    blockers = pg_blocking_pids(blocked_pid)

    if expected_blocker_pid in blockers do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        activity = pg_stat_activity(blocked_pid)

        flunk(
          "expected PostgreSQL backend #{expected_blocker_pid} to block #{blocked_pid}, pg_blocking_pids=#{inspect(blockers)}, activity=#{inspect(activity)}"
        )
      else
        Process.sleep(10)
        do_await_pg_blocking!(blocked_pid, expected_blocker_pid, deadline)
      end
    end
  end

  defp pg_stat_activity(pid) do
    Sandbox.unboxed_run(Repo, fn ->
      case Repo.query!(
             "SELECT state, wait_event_type, wait_event, left(query, 120) FROM pg_stat_activity WHERE pid = $1::int",
             [pid]
           ).rows do
        [[state, wait_event_type, wait_event, query]] ->
          %{state: state, wait_event_type: wait_event_type, wait_event: wait_event, query: query}

        _ ->
          :not_found
      end
    end)
  end

  defp pg_blocking_pids(pid) do
    Sandbox.unboxed_run(Repo, fn ->
      case Repo.query!("SELECT pg_blocking_pids($1::int)", [pid]).rows do
        [[nil]] -> []
        [[blockers]] when is_list(blockers) -> blockers
        _ -> []
      end
    end)
  end

  defp assert_configure_backend_waiting_on_lock!(configure_backend_pid) do
    activity = pg_stat_activity(configure_backend_pid)

    assert activity.wait_event_type == "Lock"
    assert activity.query =~ "FOR SHARE"
    assert activity.query =~ "courses"
  end

  defp database_backend_pid do
    Repo.query!("SELECT pg_backend_pid()").rows |> hd() |> hd()
  end

  defp release_course_blocker(blocker) do
    if Process.alive?(blocker.pid) do
      send(blocker.pid, :release_gls11_course_archive)
      Task.await(blocker, 10_000)
    end
  end

  defp cleanup_committed_catalog_fixture(event_id, course_id, staff_id) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!("DELETE FROM tee_sets WHERE course_id = $1::uuid", [Ecto.UUID.dump!(course_id)])

      Repo.query!("DELETE FROM course_holes WHERE course_id = $1::uuid", [
        Ecto.UUID.dump!(course_id)
      ])

      Repo.query!("DELETE FROM courses WHERE id = $1::uuid", [Ecto.UUID.dump!(course_id)])

      Repo.query!("DELETE FROM event_staff_assignments WHERE event_id = $1::uuid", [
        Ecto.UUID.dump!(event_id)
      ])

      Repo.query!("DELETE FROM events WHERE id = $1::uuid", [Ecto.UUID.dump!(event_id)])

      Repo.query!("DELETE FROM staff_users WHERE id = $1::uuid", [Ecto.UUID.dump!(staff_id)])
    end)
  end
end
