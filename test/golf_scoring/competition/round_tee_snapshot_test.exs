defmodule GolfScoring.Competition.RoundTeeSnapshotTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  alias Ash.Resource.Info
  alias Decimal, as: D
  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Competition
  alias GolfScoring.Competition.Event
  alias GolfScoring.Competition.Round
  alias GolfScoring.Competition.RoundTeeHoleSnapshot
  alias GolfScoring.Competition.RoundTeeProfileSnapshot
  alias GolfScoring.Competition.Services.ClearRoundTeeSnapshots
  alias GolfScoring.Competition.Services.ConfigureRoundLayout
  alias GolfScoring.Competition.Services.SnapshotRoundTeeProfiles
  alias GolfScoring.GolfCatalog
  alias GolfScoring.Repo

  @password "GLS-14 synthetic staff passphrase 2026"

  setup do
    Process.put(:gls14_prefix, "gls14-#{Ecto.UUID.generate()}")
    on_exit(fn -> Process.delete(:gls14_prefix) end)

    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  test "TDD RED: snapshot service creates one frozen 18-hole profile snapshot" do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    tee_set = create_tee_set!(event, admin, course, "White")
    profile = create_profile!(event, admin, tee_set, holes, "Men")

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes, & &1.id))

    assert {:ok, [snapshot]} =
             SnapshotRoundTeeProfiles.run(admin, round.id, [profile.id])

    assert %RoundTeeProfileSnapshot{} = snapshot
    assert snapshot.source_tee_rating_profile_id == profile.id

    hole_snapshots =
      Repo.all(
        from(h in RoundTeeHoleSnapshot,
          where: h.round_tee_profile_snapshot_id == ^snapshot.id,
          order_by: h.inserted_at
        )
      )

    assert length(hole_snapshots) == 18
  end

  test "snapshot resources register in Competition without public generic CRUD" do
    assert RoundTeeProfileSnapshot in Ash.Domain.Info.resources(Competition)
    assert RoundTeeHoleSnapshot in Ash.Domain.Info.resources(Competition)
    assert Info.action(RoundTeeProfileSnapshot, :insert_snapshot)
    refute Info.action(RoundTeeProfileSnapshot, :create)
    refute Info.action(RoundTeeHoleSnapshot, :create)
  end

  test "Competition Manager may snapshot and copies profile and per-hole values" do
    event = create_event!()
    admin = create_event_admin!(event)
    manager = create_staff_user!()
    assign_role!(admin, event, manager, :competition_manager)
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    tee_set = create_tee_set!(event, admin, course, "White")
    profile = create_profile!(event, admin, tee_set, holes, "Men", par: 5, slope: 120)

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    {:ok, route} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes, & &1.id))

    assert {:ok, [snapshot]} = SnapshotRoundTeeProfiles.run(manager, round.id, [profile.id])
    assert snapshot.slope_rating == 120
    assert snapshot.applicable_par == 5 * 18

    hole_by_round_hole =
      Repo.all(
        from(h in RoundTeeHoleSnapshot,
          where: h.round_tee_profile_snapshot_id == ^snapshot.id,
          preload: []
        )
      )
      |> Map.new(&{&1.round_hole_id, &1})

    for round_hole <- route do
      hole_snapshot = Map.fetch!(hole_by_round_hole, round_hole.id)
      assert hole_snapshot.par == 5

      assert hole_snapshot.stroke_index ==
               Enum.find(holes, &(&1.id == round_hole.course_hole_id)).hole_number
    end
  end

  test "mixed tee profiles snapshot 36 hole rows with different per-hole values" do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    white = create_tee_set!(event, admin, course, "White")
    red = create_tee_set!(event, admin, course, "Red")
    profile_a = create_profile!(event, admin, white, holes, "Men", par: 4)
    profile_b = create_profile!(event, admin, red, holes, "Women", par: 5)

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes, & &1.id))

    assert {:ok, snapshots} =
             SnapshotRoundTeeProfiles.run(admin, round.id, [profile_a.id, profile_b.id])

    assert length(snapshots) == 2

    assert Repo.aggregate(
             from(h in RoundTeeHoleSnapshot, where: h.round_id == ^round.id),
             :count
           ) == 36

    pars =
      Repo.all(
        from(h in RoundTeeHoleSnapshot,
          where: h.round_id == ^round.id,
          select: {h.round_tee_profile_snapshot_id, h.par}
        )
      )
      |> Enum.group_by(fn {snapshot_id, _} -> snapshot_id end, fn {_, par} -> par end)

    assert Enum.all?(Map.values(pars), fn values -> length(values) == 18 end)
    assert Enum.any?(pars, fn {_id, values} -> Enum.all?(values, &(&1 == 4)) end)
    assert Enum.any?(pars, fn {_id, values} -> Enum.all?(values, &(&1 == 5)) end)
  end

  test "catalog edits do not mutate existing snapshots until explicit re-snapshot" do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    tee_set = create_tee_set!(event, admin, course, "White")
    profile = create_profile!(event, admin, tee_set, holes, "Men", par: 4, slope: 113)

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes, & &1.id))

    assert {:ok, [snapshot]} = SnapshotRoundTeeProfiles.run(admin, round.id, [profile.id])
    before_profile = snapshot_values(snapshot.id)
    before_holes = hole_snapshot_values(snapshot.id)

    Repo.query!(
      "UPDATE tee_rating_profiles SET slope_rating = 140, total_par = 71 WHERE id = $1::uuid",
      [Ecto.UUID.dump!(profile.id)]
    )

    assert snapshot_values(snapshot.id) == before_profile
    assert hole_snapshot_values(snapshot.id) == before_holes

    updated_holes =
      Enum.map(holes, fn hole ->
        %{course_hole_id: hole.id, par: 3, stroke_index: hole.hole_number, distance_m: 111}
      end)

    {:ok, updated_profile} =
      GolfCatalog.configure_tee_rating_profile(
        event.id,
        %{
          tee_set_id: tee_set.id,
          rating_label: "Men",
          course_rating: D.new("70.0"),
          slope_rating: 99,
          total_par: 54,
          hole_ratings: updated_holes
        },
        actor: admin
      )

    assert snapshot_values(snapshot.id) == before_profile
    assert hole_snapshot_values(snapshot.id) == before_holes

    assert {:ok, [refreshed]} =
             SnapshotRoundTeeProfiles.run(admin, round.id, [updated_profile.id])

    assert refreshed.id == snapshot.id
    assert refreshed.slope_rating == 99
    assert Enum.all?(hole_snapshot_values(refreshed.id), fn {_id, par, _, _} -> par == 3 end)
  end

  test "desired-set reconciliation removes deselected profiles while preserving retained ids" do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    white = create_tee_set!(event, admin, course, "White")
    red = create_tee_set!(event, admin, course, "Red")
    profile_a = create_profile!(event, admin, white, holes, "Men")
    profile_b = create_profile!(event, admin, red, holes, "Women")

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes, & &1.id))

    assert {:ok, snapshots} =
             SnapshotRoundTeeProfiles.run(admin, round.id, [profile_a.id, profile_b.id])

    snap_a = Enum.find(snapshots, &(&1.source_tee_rating_profile_id == profile_a.id))
    snap_b = Enum.find(snapshots, &(&1.source_tee_rating_profile_id == profile_b.id))

    hole_ids_a = hole_snapshot_ids(snap_a.id)
    _hole_ids_b = hole_snapshot_ids(snap_b.id)

    assert {:ok, [kept]} = SnapshotRoundTeeProfiles.run(admin, round.id, [profile_a.id])
    assert kept.id == snap_a.id
    assert hole_snapshot_ids(kept.id) == hole_ids_a

    refute Repo.exists?(from(s in RoundTeeProfileSnapshot, where: s.id == ^snap_b.id))

    refute Repo.exists?(
             from(h in RoundTeeHoleSnapshot, where: h.round_tee_profile_snapshot_id == ^snap_b.id)
           )
  end

  test "snapshot validation and lifecycle guards reject invalid operations atomically" do
    event = create_event!()
    admin = create_event_admin!(event)
    staff = create_staff_user!()
    assign_role!(admin, event, staff, :registration_staff)
    system_admin = create_system_admin!()
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    tee_set = create_tee_set!(event, admin, course, "White")
    profile = create_profile!(event, admin, tee_set, holes, "Men")

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)

    assert {:error, :round_route_incomplete} =
             SnapshotRoundTeeProfiles.run(admin, round.id, [profile.id])

    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes, & &1.id))

    assert {:error, :no_tee_rating_profiles} =
             SnapshotRoundTeeProfiles.run(admin, round.id, [])

    assert {:error, :duplicate_tee_rating_profile} =
             SnapshotRoundTeeProfiles.run(admin, round.id, [profile.id, profile.id])

    assert {:error, :forbidden} = SnapshotRoundTeeProfiles.run(staff, round.id, [profile.id])

    assert {:error, :forbidden} =
             SnapshotRoundTeeProfiles.run(system_admin, round.id, [profile.id])

    assert {:ok, [snapshot]} = SnapshotRoundTeeProfiles.run(admin, round.id, [profile.id])
    before = snapshot_values(snapshot.id)

    set_round_state!(round, :scoring_open)

    assert {:error, {:invalid_round_state, "scoring_open"}} =
             SnapshotRoundTeeProfiles.run(admin, round.id, [profile.id])

    assert snapshot_values(snapshot.id) == before
  end

  test "stale Event Admin cannot snapshot after assignment revocation" do
    event = create_event!()
    admin = create_event_admin!(event)
    replacement = create_event_admin!(event)
    stale_admin = admin
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    tee_set = create_tee_set!(event, admin, course, "White")
    profile = create_profile!(event, admin, tee_set, holes, "Men")

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes, & &1.id))
    assert {:ok, [snapshot]} = SnapshotRoundTeeProfiles.run(admin, round.id, [profile.id])
    before = snapshot_values(snapshot.id)

    {:ok, _} =
      Accounts.revoke_event_staff_role(
        active_assignment(event, admin),
        actor: replacement
      )

    assert {:error, :forbidden} =
             SnapshotRoundTeeProfiles.run(stale_admin, round.id, [profile.id])

    assert snapshot_values(snapshot.id) == before
  end

  test "cross-course tee profile is rejected" do
    event = create_event!()
    admin = create_event_admin!(event)
    course_a = create_course!(event, admin, "A")
    course_b = create_course!(event, admin, "B")
    holes_a = create_eighteen_holes!(event, admin, course_a)
    tee_set_b = create_tee_set!(event, admin, course_b, "Red")

    profile_b =
      create_profile!(
        event,
        admin,
        tee_set_b,
        create_eighteen_holes!(event, admin, course_b),
        "Women"
      )

    {:ok, round} = Competition.create_round(event.id, course_a.id, actor: admin)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes_a, & &1.id))

    assert {:error, :cross_course_tee_profile} =
             SnapshotRoundTeeProfiles.run(admin, round.id, [profile_b.id])
  end

  test "route structural change is blocked while snapshots exist" do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    tee_set = create_tee_set!(event, admin, course, "White")
    profile = create_profile!(event, admin, tee_set, holes, "Men")

    {:ok, spare_hole} =
      GolfCatalog.configure_course_hole(
        event.id,
        %{course_id: course.id, hole_number: 19},
        actor: admin
      )

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    route_ids = Enum.map(holes, & &1.id)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, route_ids)
    assert {:ok, [_]} = SnapshotRoundTeeProfiles.run(admin, round.id, [profile.id])

    swapped = [spare_hole.id | Enum.take(route_ids, 17)]

    assert {:error, :round_snapshots_block_route_change} =
             ConfigureRoundLayout.run(admin, round.id, swapped)
  end

  test "explicit clear allows structural route change in draft|ready" do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    tee_set = create_tee_set!(event, admin, course, "White")
    profile = create_profile!(event, admin, tee_set, holes, "Men")

    {:ok, spare_hole} =
      GolfCatalog.configure_course_hole(
        event.id,
        %{course_id: course.id, hole_number: 19},
        actor: admin
      )

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    route_ids = Enum.map(holes, & &1.id)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, route_ids)
    assert {:ok, [_]} = SnapshotRoundTeeProfiles.run(admin, round.id, [profile.id])

    swapped = [spare_hole.id | Enum.take(route_ids, 17)]

    assert {:error, :round_snapshots_block_route_change} =
             ConfigureRoundLayout.run(admin, round.id, swapped)

    assert {:ok, []} = ClearRoundTeeSnapshots.run(admin, round.id)
    assert {:ok, _} = ConfigureRoundLayout.run(admin, round.id, swapped)
  end

  @tag :real_concurrency
  test "ClearRoundTeeSnapshots and ConfigureRoundLayout serialize without deadlock or partial state" do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    tee_set = create_tee_set!(event, admin, course, "White")
    profile = create_profile!(event, admin, tee_set, holes, "Men")

    {:ok, spare_hole} =
      GolfCatalog.configure_course_hole(
        event.id,
        %{course_id: course.id, hole_number: 19},
        actor: admin
      )

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    route_ids = Enum.map(holes, & &1.id)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, route_ids)
    assert {:ok, [_]} = SnapshotRoundTeeProfiles.run(admin, round.id, [profile.id])

    swapped = [spare_hole.id | Enum.take(route_ids, 17)]
    original_set = MapSet.new(route_ids)
    swapped_set = MapSet.new(swapped)
    test_pid = self()

    for _ <- 1..8 do
      assert round_profile_snapshot_count(round.id) == 1
      assert MapSet.new(round_route_course_hole_ids(round.id)) == original_set

      clear_task =
        Task.async(fn ->
          Sandbox.allow(Repo, test_pid, self())
          ClearRoundTeeSnapshots.run(%{id: admin.id}, round.id)
        end)

      route_task =
        Task.async(fn ->
          Sandbox.allow(Repo, test_pid, self())
          ConfigureRoundLayout.run(%{id: admin.id}, round.id, swapped)
        end)

      clear_result = Task.await(clear_task, 30_000)
      route_result = Task.await(route_task, 30_000)

      refute gls14_deadlock_result?(clear_result)
      refute gls14_deadlock_result?(route_result)
      refute gls14_foreign_key_result?(clear_result)
      refute gls14_foreign_key_result?(route_result)
      assert gls14_valid_route_result?(route_result)
      assert match?({:ok, []}, clear_result)

      after_snapshots = round_profile_snapshot_count(round.id)
      after_set = MapSet.new(round_route_course_hole_ids(round.id))

      case {after_snapshots, route_result} do
        {0, {:ok, _}} ->
          assert after_set == swapped_set

        {0, {:error, :round_snapshots_block_route_change}} ->
          assert after_set == original_set

        _ ->
          flunk(
            "unexpected concurrent end state snapshots=#{after_snapshots} route=#{inspect(route_result)}"
          )
      end

      {:ok, _} = ConfigureRoundLayout.run(admin, round.id, route_ids)
      assert {:ok, [_]} = SnapshotRoundTeeProfiles.run(admin, round.id, [profile.id])
    end
  end

  test "missing route-hole rating is rejected without mutating snapshots" do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    tee_set = create_tee_set!(event, admin, course, "White")

    partial_ratings =
      holes
      |> Enum.take(17)
      |> Enum.map(fn hole ->
        %{course_hole_id: hole.id, par: 4, stroke_index: hole.hole_number, distance_m: 300}
      end)

    {:ok, partial_profile} =
      GolfCatalog.configure_tee_rating_profile(
        event.id,
        %{
          tee_set_id: tee_set.id,
          rating_label: "Partial",
          course_rating: D.new("72.0"),
          slope_rating: 113,
          total_par: 68,
          hole_ratings: partial_ratings
        },
        actor: admin
      )

    full_profile = create_profile!(event, admin, tee_set, holes, "Full")

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes, & &1.id))
    assert {:ok, [existing]} = SnapshotRoundTeeProfiles.run(admin, round.id, [full_profile.id])
    before = snapshot_values(existing.id)

    assert {:error, :missing_round_hole_rating} =
             SnapshotRoundTeeProfiles.run(admin, round.id, [partial_profile.id])

    assert snapshot_values(existing.id) == before
  end

  test "extra source hole ratings outside the round route remain valid" do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    tee_set = create_tee_set!(event, admin, course, "White")

    {:ok, spare_hole} =
      GolfCatalog.configure_course_hole(
        event.id,
        %{course_id: course.id, hole_number: 19},
        actor: admin
      )

    ratings =
      Enum.map(holes, fn hole ->
        %{course_hole_id: hole.id, par: 4, stroke_index: hole.hole_number, distance_m: 300}
      end) ++
        [%{course_hole_id: spare_hole.id, par: 5, stroke_index: 1, distance_m: 400}]

    {:ok, profile} =
      GolfCatalog.configure_tee_rating_profile(
        event.id,
        %{
          tee_set_id: tee_set.id,
          rating_label: "ExtraSource",
          course_rating: D.new("72.0"),
          slope_rating: 113,
          total_par: 77,
          hole_ratings: ratings
        },
        actor: admin
      )

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes, & &1.id))

    assert {:ok, [_snapshot]} = SnapshotRoundTeeProfiles.run(admin, round.id, [profile.id])
  end

  test "stale Competition Manager cannot snapshot after assignment revocation" do
    event = create_event!()
    admin = create_event_admin!(event)
    manager = create_staff_user!()
    assign_role!(admin, event, manager, :competition_manager)
    stale_manager = manager
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    tee_set = create_tee_set!(event, admin, course, "White")
    profile = create_profile!(event, admin, tee_set, holes, "Men")

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes, & &1.id))

    {:ok, _} =
      Accounts.revoke_event_staff_role(
        active_assignment(event, manager, :competition_manager),
        actor: admin
      )

    assert {:error, :forbidden} =
             SnapshotRoundTeeProfiles.run(stale_manager, round.id, [profile.id])
  end

  test "protected round states reject snapshot mutations" do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    tee_set = create_tee_set!(event, admin, course, "White")
    profile = create_profile!(event, admin, tee_set, holes, "Men")

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes, & &1.id))

    for state <- [:scoring_closed, :finalized, :cancelled] do
      set_round_state!(round, state)
      state_string = Atom.to_string(state)

      assert {:error, {:invalid_round_state, ^state_string}} =
               SnapshotRoundTeeProfiles.run(admin, round.id, [profile.id])
    end
  end

  test "multi-profile snapshot rolls back atomically on failure" do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    white = create_tee_set!(event, admin, course, "White")
    red = create_tee_set!(event, admin, course, "Red")
    profile_a = create_profile!(event, admin, white, holes, "Men")
    profile_b = create_profile!(event, admin, red, holes, "Women")

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes, & &1.id))
    assert {:ok, [_existing]} = SnapshotRoundTeeProfiles.run(admin, round.id, [profile_a.id])

    before_profiles = round_profile_snapshot_state(round.id)
    before_holes = round_hole_snapshot_state(round.id)

    install_hole_snapshot_failure_trigger!(round.id, 18)

    try do
      assert {:error, _} =
               SnapshotRoundTeeProfiles.run(admin, round.id, [profile_a.id, profile_b.id])
    after
      drop_hole_snapshot_failure_trigger!()
    end

    after_profiles = round_profile_snapshot_state(round.id)
    after_holes = round_hole_snapshot_state(round.id)

    assert after_profiles.count == before_profiles.count
    assert after_profiles.ids == before_profiles.ids
    assert after_profiles.values == before_profiles.values
    assert after_holes.count == before_holes.count
    assert after_holes.ids == before_holes.ids
    assert after_holes.values == before_holes.values

    refute Repo.exists?(
             from(s in RoundTeeProfileSnapshot,
               where: s.round_id == ^round.id and s.source_tee_rating_profile_id == ^profile_b.id
             )
           )
  end

  test "PostgreSQL composite and uniqueness constraints are enforced independently" do
    fixture = snapshot_constraint_fixture!()

    assert_constraint_violation(
      fn ->
        Repo.query!(
          """
          INSERT INTO round_tee_profile_snapshots
            (round_id, course_id, source_tee_set_id, source_tee_rating_profile_id,
             tee_set_name, rating_label, course_rating, slope_rating, total_par, applicable_par,
             source_tee_set_updated_at, source_tee_rating_profile_updated_at)
          VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, 'X', 'Y', 72.0, 113, 72, 72, now(), now())
          """,
          [
            Ecto.UUID.dump!(fixture.round_a.id),
            Ecto.UUID.dump!(fixture.course_b.id),
            Ecto.UUID.dump!(fixture.tee_set_b.id),
            Ecto.UUID.dump!(fixture.profile_b.id)
          ]
        )
      end,
      "round_tee_profile_snapshots_round_id_fkey"
    )

    assert_constraint_violation(
      fn ->
        Repo.query!(
          """
          INSERT INTO round_tee_profile_snapshots
            (round_id, course_id, source_tee_set_id, source_tee_rating_profile_id,
             tee_set_name, rating_label, course_rating, slope_rating, total_par, applicable_par,
             source_tee_set_updated_at, source_tee_rating_profile_updated_at)
          VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, 'X', 'Y', 72.0, 113, 72, 72, now(), now())
          """,
          [
            Ecto.UUID.dump!(fixture.round_b.id),
            Ecto.UUID.dump!(fixture.course_b.id),
            Ecto.UUID.dump!(fixture.tee_set_a.id),
            Ecto.UUID.dump!(fixture.profile_a.id)
          ]
        )
      end,
      "round_tee_profile_snapshots_source_tee_set_id_fkey"
    )

    assert_constraint_violation(
      fn ->
        Repo.query!(
          """
          INSERT INTO round_tee_profile_snapshots
            (round_id, course_id, source_tee_set_id, source_tee_rating_profile_id,
             tee_set_name, rating_label, course_rating, slope_rating, total_par, applicable_par,
             source_tee_set_updated_at, source_tee_rating_profile_updated_at)
          VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, 'X', 'Y', 72.0, 113, 72, 72, now(), now())
          """,
          [
            Ecto.UUID.dump!(fixture.round_b.id),
            Ecto.UUID.dump!(fixture.course_b.id),
            Ecto.UUID.dump!(fixture.tee_set_b2.id),
            Ecto.UUID.dump!(fixture.profile_b1.id)
          ]
        )
      end,
      "round_tee_profile_snapshots_source_tee_rating_profile_id_fkey"
    )

    {:ok, [existing | _]} =
      SnapshotRoundTeeProfiles.run(fixture.admin, fixture.round_b.id, [fixture.profile_b.id])

    assert_constraint_violation(
      fn ->
        Repo.query!(
          """
          INSERT INTO round_tee_profile_snapshots
            (round_id, course_id, source_tee_set_id, source_tee_rating_profile_id,
             tee_set_name, rating_label, course_rating, slope_rating, total_par, applicable_par,
             source_tee_set_updated_at, source_tee_rating_profile_updated_at)
          VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, 'Dup', 'Dup', 72.0, 113, 72, 72, now(), now())
          """,
          [
            Ecto.UUID.dump!(fixture.round_b.id),
            Ecto.UUID.dump!(fixture.course_b.id),
            Ecto.UUID.dump!(fixture.tee_set_b.id),
            Ecto.UUID.dump!(fixture.profile_b.id)
          ]
        )
      end,
      "round_tee_profile_snapshots_source_profile_idx"
    )

    round_hole_b = hd(fixture.route_b).id
    round_hole_a = hd(fixture.route_a).id

    assert_constraint_violation(
      fn ->
        Repo.query!(
          """
          INSERT INTO round_tee_hole_snapshots
            (round_tee_profile_snapshot_id, round_id, round_hole_id, par, stroke_index)
          VALUES ($1::uuid, $2::uuid, $3::uuid, 4, 1)
          """,
          [
            Ecto.UUID.dump!(existing.id),
            Ecto.UUID.dump!(fixture.round_a.id),
            Ecto.UUID.dump!(round_hole_a)
          ]
        )
      end,
      "round_tee_hole_snapshots_round_tee_profile_snapshot_id_fkey"
    )

    assert_constraint_violation(
      fn ->
        Repo.query!(
          """
          INSERT INTO round_tee_hole_snapshots
            (round_tee_profile_snapshot_id, round_id, round_hole_id, par, stroke_index)
          VALUES ($1::uuid, $2::uuid, $3::uuid, 4, 1)
          """,
          [
            Ecto.UUID.dump!(existing.id),
            Ecto.UUID.dump!(fixture.round_b.id),
            Ecto.UUID.dump!(round_hole_a)
          ]
        )
      end,
      "round_tee_hole_snapshots_round_hole_id_fkey"
    )

    assert_constraint_violation(
      fn ->
        Repo.query!(
          """
          INSERT INTO round_tee_hole_snapshots
            (round_tee_profile_snapshot_id, round_id, round_hole_id, par, stroke_index)
          VALUES ($1::uuid, $2::uuid, $3::uuid, 4, 1)
          """,
          [
            Ecto.UUID.dump!(existing.id),
            Ecto.UUID.dump!(fixture.round_b.id),
            Ecto.UUID.dump!(round_hole_b)
          ]
        )
      end,
      "round_tee_hole_snapshots_unique_hole_per_profile_snapshot_index"
    )
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

  defp create_staff_user! do
    email = "#{Process.get(:gls14_prefix)}-#{System.unique_integer([:positive])}@example.com"

    GolfScoring.Accounts.StaffUser
    |> Ash.Changeset.for_create(:provision_staff_user, %{
      email: email,
      password: @password,
      password_confirmation: @password
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_course!(event, admin, suffix \\ "Main") do
    {:ok, course} =
      GolfCatalog.create_course(
        event.id,
        %{name: "Test Course #{suffix}", location: "ZA"},
        actor: admin
      )

    course
  end

  defp create_eighteen_holes!(event, admin, course) do
    for n <- 1..18 do
      {:ok, hole} =
        GolfCatalog.configure_course_hole(
          event.id,
          %{course_id: course.id, hole_number: n},
          actor: admin
        )

      hole
    end
  end

  defp create_tee_set!(event, admin, course, name) do
    {:ok, tee_set} =
      GolfCatalog.configure_tee_set(event.id, %{course_id: course.id, name: name}, actor: admin)

    tee_set
  end

  defp create_profile!(event, admin, tee_set, holes, label, opts \\ []) do
    par = Keyword.get(opts, :par, 4)
    slope = Keyword.get(opts, :slope, 113)

    hole_ratings =
      Enum.map(holes, fn hole ->
        %{
          course_hole_id: hole.id,
          par: par,
          stroke_index: hole.hole_number,
          distance_m: 300 + hole.hole_number
        }
      end)

    {:ok, profile} =
      GolfCatalog.configure_tee_rating_profile(
        event.id,
        %{
          tee_set_id: tee_set.id,
          rating_label: label,
          course_rating: D.new("72.0"),
          slope_rating: slope,
          total_par: par * 18,
          hole_ratings: hole_ratings
        },
        actor: admin
      )

    profile
  end

  defp assign_role!(actor, event, staff, role) do
    {:ok, _} =
      Accounts.assign_event_staff_role(
        %{event_id: event.id, staff_user_id: staff.id, role: role},
        actor: actor
      )
  end

  defp create_system_admin! do
    staff = create_staff_user!()

    Repo.query!("UPDATE staff_users SET system_admin = TRUE WHERE id = $1::uuid", [
      Ecto.UUID.dump!(staff.id)
    ])

    Repo.get!(GolfScoring.Accounts.StaffUser, staff.id)
  end

  defp set_round_state!(round, state) do
    Repo.query!("UPDATE rounds SET state = $1 WHERE id = $2::uuid", [
      Atom.to_string(state),
      Ecto.UUID.dump!(round.id)
    ])

    Repo.get!(Round, round.id)
  end

  defp snapshot_values(snapshot_id) do
    [[rating_label, slope, applicable_par]] =
      Repo.query!(
        """
        SELECT rating_label, slope_rating, applicable_par
        FROM round_tee_profile_snapshots WHERE id = $1::uuid
        """,
        [Ecto.UUID.dump!(snapshot_id)]
      ).rows

    {rating_label, slope, applicable_par}
  end

  defp hole_snapshot_values(snapshot_id) do
    Repo.query!(
      """
      SELECT round_hole_id::text, par, stroke_index, distance_m
      FROM round_tee_hole_snapshots
      WHERE round_tee_profile_snapshot_id = $1::uuid
      ORDER BY round_hole_id
      """,
      [Ecto.UUID.dump!(snapshot_id)]
    ).rows
    |> Enum.map(fn [round_hole_id, par, stroke_index, distance_m] ->
      {Ecto.UUID.cast!(round_hole_id), par, stroke_index, distance_m}
    end)
  end

  defp hole_snapshot_ids(snapshot_id) do
    Repo.query!(
      "SELECT id::text, round_hole_id::text FROM round_tee_hole_snapshots WHERE round_tee_profile_snapshot_id = $1::uuid ORDER BY round_hole_id",
      [Ecto.UUID.dump!(snapshot_id)]
    ).rows
    |> Map.new(fn [id, round_hole_id] ->
      {Ecto.UUID.cast!(round_hole_id), Ecto.UUID.cast!(id)}
    end)
  end

  defp round_profile_snapshot_state(round_id) do
    rows =
      Repo.query!(
        """
        SELECT id::text, source_tee_rating_profile_id::text, rating_label, course_rating::text,
               slope_rating, total_par, applicable_par
        FROM round_tee_profile_snapshots
        WHERE round_id = $1::uuid
        ORDER BY id
        """,
        [Ecto.UUID.dump!(round_id)]
      ).rows

    ids = Enum.map(rows, fn [id | _] -> Ecto.UUID.cast!(id) end)

    values =
      Enum.map(rows, fn [_id, source_id, label, course_rating, slope, total_par, applicable_par] ->
        {Ecto.UUID.cast!(source_id), label, course_rating, slope, total_par, applicable_par}
      end)

    %{count: length(rows), ids: ids, values: values}
  end

  defp round_hole_snapshot_state(round_id) do
    rows =
      Repo.query!(
        """
        SELECT id::text, round_tee_profile_snapshot_id::text, round_hole_id::text,
               par, stroke_index, distance_m
        FROM round_tee_hole_snapshots
        WHERE round_id = $1::uuid
        ORDER BY id
        """,
        [Ecto.UUID.dump!(round_id)]
      ).rows

    ids = Enum.map(rows, fn [id | _] -> Ecto.UUID.cast!(id) end)

    values =
      Enum.map(rows, fn [_id, profile_snap_id, round_hole_id, par, stroke_index, distance_m] ->
        {Ecto.UUID.cast!(profile_snap_id), Ecto.UUID.cast!(round_hole_id), par, stroke_index,
         distance_m}
      end)

    %{count: length(rows), ids: ids, values: values}
  end

  defp snapshot_constraint_fixture! do
    event = create_event!()
    admin = create_event_admin!(event)
    course_a = create_course!(event, admin, "A")
    course_b = create_course!(event, admin, "B")
    holes_a = create_eighteen_holes!(event, admin, course_a)
    holes_b = create_eighteen_holes!(event, admin, course_b)
    tee_set_a = create_tee_set!(event, admin, course_a, "A-White")
    tee_set_b1 = create_tee_set!(event, admin, course_b, "B-White-1")
    tee_set_b2 = create_tee_set!(event, admin, course_b, "B-White-2")
    profile_a = create_profile!(event, admin, tee_set_a, holes_a, "A-Men")
    profile_b1 = create_profile!(event, admin, tee_set_b1, holes_b, "B-Men-1")
    profile_b = create_profile!(event, admin, tee_set_b1, holes_b, "B-Men-dup")

    {:ok, round_a} = Competition.create_round(event.id, course_a.id, actor: admin)
    {:ok, round_b} = Competition.create_round(event.id, course_b.id, actor: admin)
    {:ok, route_a} = ConfigureRoundLayout.run(admin, round_a.id, Enum.map(holes_a, & &1.id))
    {:ok, route_b} = ConfigureRoundLayout.run(admin, round_b.id, Enum.map(holes_b, & &1.id))

    %{
      admin: admin,
      course_a: course_a,
      course_b: course_b,
      round_a: round_a,
      round_b: round_b,
      route_a: route_a,
      route_b: route_b,
      tee_set_a: tee_set_a,
      tee_set_b: tee_set_b1,
      tee_set_b1: tee_set_b1,
      tee_set_b2: tee_set_b2,
      profile_a: profile_a,
      profile_b1: profile_b1,
      profile_b: profile_b
    }
  end

  defp active_assignment(event, staff, role \\ :event_admin) do
    [[assignment_id]] =
      Repo.query!(
        "SELECT id::text FROM event_staff_assignments WHERE event_id = $1::uuid AND staff_user_id = $2::uuid AND role = $3 AND status = 'active'",
        [
          Ecto.UUID.dump!(event.id),
          Ecto.UUID.dump!(staff.id),
          Atom.to_string(role)
        ]
      ).rows

    Accounts.EventStaffAssignment
    |> Ash.get!(assignment_id, authorize?: false)
  end

  defp round_profile_snapshot_count(round_id) do
    [[count]] =
      Repo.query!(
        "SELECT count(*) FROM round_tee_profile_snapshots WHERE round_id = $1::uuid",
        [Ecto.UUID.dump!(round_id)]
      ).rows

    count
  end

  defp round_route_course_hole_ids(round_id) do
    Repo.query!(
      """
      SELECT course_hole_id::text
      FROM round_holes
      WHERE round_id = $1::uuid
      ORDER BY play_order
      """,
      [Ecto.UUID.dump!(round_id)]
    ).rows
    |> Enum.map(fn [id] -> Ecto.UUID.cast!(id) end)
  end

  defp gls14_valid_route_result?({:ok, _}), do: true
  defp gls14_valid_route_result?({:error, :round_snapshots_block_route_change}), do: true
  defp gls14_valid_route_result?(_), do: false

  defp gls14_deadlock_result?({:error, %Postgrex.Error{postgres: %{code: :deadlock_detected}}}),
    do: true

  defp gls14_deadlock_result?(_), do: false

  defp gls14_foreign_key_result?(
         {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}}
       ),
       do: true

  defp gls14_foreign_key_result?(_), do: false

  defp install_hole_snapshot_failure_trigger!(_round_id, max_rows) do
    Repo.query!("""
    CREATE OR REPLACE FUNCTION gls14_fail_hole_snapshots() RETURNS trigger
    LANGUAGE plpgsql AS $$
    DECLARE existing bigint;
    BEGIN
      SELECT count(*) INTO existing
      FROM round_tee_hole_snapshots
      WHERE round_id = NEW.round_id;

      IF existing >= #{max_rows} THEN
        RAISE EXCEPTION 'gls14 simulated hole snapshot failure';
      END IF;
      RETURN NEW;
    END;
    $$;
    """)

    Repo.query!("""
    CREATE TRIGGER gls14_fail_hole_snapshots
    BEFORE INSERT ON round_tee_hole_snapshots
    FOR EACH ROW EXECUTE FUNCTION gls14_fail_hole_snapshots()
    """)
  end

  defp drop_hole_snapshot_failure_trigger! do
    Repo.query!("DROP TRIGGER IF EXISTS gls14_fail_hole_snapshots ON round_tee_hole_snapshots")
    Repo.query!("DROP FUNCTION IF EXISTS gls14_fail_hole_snapshots()")
  end

  defp assert_constraint_violation(fun, expected_constraint) do
    error = assert_raise Postgrex.Error, fun

    assert error.postgres.code == :foreign_key_violation or
             error.postgres.code == :unique_violation or
             error.postgres.code == :check_violation

    assert error.postgres.constraint == expected_constraint
  end
end
