defmodule GolfScoring.Scoring.HandicapRecordsTest do
  use ExUnit.Case, async: false

  require Ash.Query

  alias Ash.Resource.Info
  alias Decimal, as: D
  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Audit.AuditEvent
  alias GolfScoring.Competition
  alias GolfScoring.Competition.Event
  alias GolfScoring.Competition.Player
  alias GolfScoring.Competition.Round
  alias GolfScoring.Competition.Services.ConfigureRoundCompetition
  alias GolfScoring.Competition.Services.ConfigureRoundLayout
  alias GolfScoring.Competition.Services.SnapshotRoundTeeProfiles
  alias GolfScoring.GolfCatalog
  alias GolfScoring.Repo
  alias GolfScoring.Scoring
  alias GolfScoring.Scoring.CompetitionHandicap
  alias GolfScoring.Scoring.HandicapSnapshot

  @password "GLS-22 synthetic staff passphrase 2026"

  setup do
    Process.put(:gls22_prefix, "gls22-#{Ecto.UUID.generate()}")
    on_exit(fn -> Process.delete(:gls22_prefix) end)

    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  test "Scoring domain registers only expected GLS-22 resources" do
    resources = Ash.Domain.Info.resources(Scoring)
    assert HandicapSnapshot in resources
    assert CompetitionHandicap in resources
    assert length(resources) == 2
    refute Info.action(HandicapSnapshot, :create)
    refute Info.action(CompetitionHandicap, :create)
  end

  test "handicap resources expose named internal actions only" do
    refute Info.action(HandicapSnapshot, :create)
    refute Info.action(HandicapSnapshot, :update)
    refute Info.action(HandicapSnapshot, :destroy)
    refute Info.action(CompetitionHandicap, :create)
    refute Info.action(CompetitionHandicap, :destroy)

    assert Info.action(HandicapSnapshot, :create_configured_internal)
    assert Info.action(CompetitionHandicap, :build_internal)
  end

  test "assign_round_tee authorizes managers only and allows scoring_open round" do
    setup = setup_round_with_tees!()
    staff = create_staff_user!()
    assign_role!(setup.admin, setup.event, staff, :registration_staff)

    assert {:error, :forbidden} =
             Competition.assign_round_tee(
               staff,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               setup.tee_a.id
             )

    scoring_open = set_round_state!(setup.round, :scoring_open)

    assert {:ok, assigned} =
             Competition.assign_round_tee(
               setup.admin,
               setup.event.id,
               scoring_open.id,
               setup.entry.id,
               setup.tee_a.id
             )

    assert assigned.round_tee_profile_snapshot_id == setup.tee_a.id
  end

  test "cross-round tee assignment fails at database layer" do
    setup = setup_round_with_tees!()
    other = setup_round_with_tees!()

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        """
        UPDATE round_entries
        SET round_tee_profile_snapshot_id = $1::uuid
        WHERE id = $2::uuid
        """,
        [Ecto.UUID.dump!(other.tee_a.id), Ecto.UUID.dump!(setup.entry.id)]
      )
    end
  end

  test "started entry rejects ordinary tee and handicap mutation" do
    setup = setup_round_with_tees!()

    force_participation!(setup.entry.id, :active)

    assert {:error, :entry_not_not_started} =
             Competition.assign_round_tee(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               setup.tee_a.id
             )

    assert {:error, :entry_not_not_started} =
             Scoring.confirm_handicap_input(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               %{source_handicap_index: D.new("12.4")}
             )
  end

  test "official HI is distinguishable from committee deemed basis" do
    setup = setup_round_with_tees!(assign_tee: true)

    assert {:ok, official} =
             Scoring.confirm_handicap_input(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               %{source_handicap_index: D.new("10.2")}
             )

    assert official.basis_source == :official_or_preloaded
    assert official.source_handicap_index == D.new("10.2")
    assert is_nil(official.deemed_handicap_basis)

    entry2 = add_entry!(setup)

    assert {:ok, _} =
             Competition.assign_round_tee(
               setup.admin,
               setup.event.id,
               setup.round.id,
               entry2.id,
               setup.tee_a.id
             )

    assert {:ok, deemed} =
             Scoring.apply_no_hi_policy(
               setup.admin,
               setup.event.id,
               setup.round.id,
               entry2.id,
               %{deemed_handicap_basis: D.new("18.0"), policy_reference: "committee discretion"}
             )

    assert deemed.basis_source == :committee_deemed
    assert deemed.deemed_handicap_basis == D.new("18.0")
    assert is_nil(deemed.source_handicap_index)
  end

  test "player declared source records round entry confirmer" do
    setup = setup_round_with_tees!(assign_tee: true)

    assert {:ok, snapshot} =
             Scoring.confirm_handicap_input(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               %{source_handicap_index: D.new("8.1")},
               basis_source: :player_declared,
               confirmer: :player_entry
             )

    assert snapshot.basis_source == :player_declared
    assert snapshot.confirmed_by_round_entry_id == setup.entry.id
    assert is_nil(snapshot.confirmed_by_staff_user_id)
  end

  test "missing HI does not silently default to 14 or 20" do
    setup = setup_round_with_tees!(assign_tee: true)

    assert {:error, :deemed_handicap_basis_required} =
             Scoring.apply_no_hi_policy(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               %{policy_reference: "no default"}
             )

    assert [] =
             Repo.query!(
               "SELECT deemed_handicap_basis FROM handicap_snapshots WHERE round_entry_id = $1::uuid",
               [Ecto.UUID.dump!(setup.entry.id)]
             ).rows
  end

  test "committee override requires reason and staff authorization" do
    setup = setup_round_with_tees!(assign_tee: true)
    staff = create_staff_user!()
    assign_role!(setup.admin, setup.event, staff, :registration_staff)

    assert {:error, :forbidden} =
             Scoring.override_handicap_basis(
               staff,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               %{deemed_handicap_basis: D.new("16.0"), override_reason: "known ability"}
             )

    assert {:error, :override_reason_required} =
             Scoring.override_handicap_basis(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               %{deemed_handicap_basis: D.new("16.0"), override_reason: "  "}
             )
  end

  test "override audit and mutation are atomic" do
    setup = setup_round_with_tees!(assign_tee: true)
    before = audit_count()

    assert {:ok, snapshot} =
             Scoring.override_handicap_basis(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               %{
                 deemed_handicap_basis: D.new("15.5"),
                 override_reason: "committee correction"
               }
             )

    assert snapshot.basis_source == :committee_override
    assert audit_count() == before + 1

    assert [%AuditEvent{action: "override_handicap_basis"}] =
             AuditEvent
             |> Ash.Query.filter(
               target_id == ^setup.entry.id and action == "override_handicap_basis"
             )
             |> Ash.read!(authorize?: false)
  end

  test "build_handicap_snapshot copies tee facts and stores supplied course handicaps only" do
    setup = setup_round_with_tees!(assign_tee: true)

    assert {:ok, _} =
             Scoring.confirm_handicap_input(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               %{source_handicap_index: D.new("11.0")}
             )

    assert {:ok, built} =
             Scoring.build_handicap_snapshot(setup.entry.id, %{
               course_handicap_unrounded: D.new("12.3"),
               course_handicap_rounded: 12
             })

    assert built.course_rating == setup.tee_a.course_rating
    assert built.slope_rating == setup.tee_a.slope_rating
    assert built.applicable_par == setup.tee_a.applicable_par
    assert built.course_handicap_unrounded == D.new("12.3")
    assert built.course_handicap_rounded == 12
    assert built.built_at
  end

  test "mixed tees produce independent handicap snapshots" do
    setup = setup_round_with_tees!(profiles: 2, entries: 2)
    [entry_a, entry_b] = setup.entries

    assert {:ok, _} =
             Competition.assign_round_tee(
               setup.admin,
               setup.event.id,
               setup.round.id,
               entry_a.id,
               setup.tee_a.id
             )

    assert {:ok, _} =
             Competition.assign_round_tee(
               setup.admin,
               setup.event.id,
               setup.round.id,
               entry_b.id,
               setup.tee_b.id
             )

    assert {:ok, snap_a} =
             Scoring.confirm_handicap_input(
               setup.admin,
               setup.event.id,
               setup.round.id,
               entry_a.id,
               %{source_handicap_index: D.new("9.0")}
             )

    assert {:ok, snap_b} =
             Scoring.confirm_handicap_input(
               setup.admin,
               setup.event.id,
               setup.round.id,
               entry_b.id,
               %{source_handicap_index: D.new("21.0")}
             )

    assert snap_a.round_tee_profile_snapshot_id == setup.tee_a.id
    assert snap_b.round_tee_profile_snapshot_id == setup.tee_b.id
    assert snap_a.id != snap_b.id
  end

  test "PostgreSQL rejects duplicate base handicap snapshot per entry" do
    setup = setup_round_with_tees!(assign_tee: true)

    assert {:ok, _} =
             Scoring.confirm_handicap_input(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               %{source_handicap_index: D.new("7.0")}
             )

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO handicap_snapshots
            (round_id, round_entry_id, round_tee_profile_snapshot_id, basis_source,
             source_handicap_index, inserted_at, updated_at)
          VALUES ($1::uuid, $2::uuid, $3::uuid, 'official_or_preloaded', 7.0, now(), now())
          """,
          [
            Ecto.UUID.dump!(setup.round.id),
            Ecto.UUID.dump!(setup.entry.id),
            Ecto.UUID.dump!(setup.tee_a.id)
          ]
        )
      end

    assert error.postgres.code == :unique_violation
    assert error.postgres.constraint == "handicap_snapshots_unique_base_per_entry_index"
  end

  test "PostgreSQL rejects cross-round handicap snapshot ownership" do
    setup = setup_round_with_tees!(assign_tee: true)
    other = setup_round_with_tees!()

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO handicap_snapshots
            (round_id, round_entry_id, round_tee_profile_snapshot_id, basis_source,
             source_handicap_index, inserted_at, updated_at)
          VALUES ($1::uuid, $2::uuid, $3::uuid, 'official_or_preloaded', 7.0, now(), now())
          """,
          [
            Ecto.UUID.dump!(other.round.id),
            Ecto.UUID.dump!(setup.entry.id),
            Ecto.UUID.dump!(setup.tee_a.id)
          ]
        )
      end

    assert error.postgres.code == :foreign_key_violation
  end

  test "build_competition_handicap persists allowance from RoundCompetition" do
    setup = setup_round_with_tees!(assign_tee: true, competition: true)

    assert {:ok, _} =
             Scoring.confirm_handicap_input(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               %{source_handicap_index: D.new("10.0")}
             )

    assert {:ok, _} =
             Scoring.build_handicap_snapshot(setup.entry.id, %{
               course_handicap_unrounded: D.new("11.0"),
               course_handicap_rounded: 11
             })

    assert {:ok, competition_row} =
             Scoring.build_competition_handicap(setup.entry.id, setup.competition.id, %{
               playing_handicap: 10,
               policy_identifier: "gls22_test_policy_v1",
               allowance_applied: true
             })

    assert competition_row.handicap_allowance_percent ==
             setup.competition.handicap_allowance_percent

    assert competition_row.playing_handicap == 10
  end

  test "PostgreSQL enforces unique competition handicap per entry and competition" do
    setup = setup_round_with_tees!(assign_tee: true, competition: true)
    build_built_snapshot!(setup)

    assert {:ok, first} =
             Scoring.build_competition_handicap(setup.entry.id, setup.competition.id, %{
               playing_handicap: 8,
               policy_identifier: "policy_a"
             })

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO competition_handicaps
            (round_id, round_entry_id, round_competition_id, handicap_snapshot_id,
             handicap_allowance_percent, allowance_applied, playing_handicap, policy_identifier,
             inserted_at, updated_at)
          VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, 100, true, 9, 'policy_b', now(), now())
          """,
          [
            Ecto.UUID.dump!(setup.round.id),
            Ecto.UUID.dump!(setup.entry.id),
            Ecto.UUID.dump!(setup.competition.id),
            Ecto.UUID.dump!(first.handicap_snapshot_id)
          ]
        )
      end

    assert error.postgres.constraint == "competition_handicaps_unique_entry_competition_index"
  end

  test "pre-start basis change clears stale built and competition handicap output" do
    setup = setup_round_with_tees!(assign_tee: true, competition: true)
    build_built_snapshot!(setup)

    assert {:ok, _} =
             Scoring.build_competition_handicap(setup.entry.id, setup.competition.id, %{
               playing_handicap: 7,
               policy_identifier: "policy_keep"
             })

    assert competition_count(setup.entry.id) == 1

    assert {:ok, _} =
             Scoring.override_handicap_basis(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               %{deemed_handicap_basis: D.new("13.0"), override_reason: "correct basis"}
             )

    snapshot = fetch_snapshot!(setup.entry.id)
    assert is_nil(snapshot.built_at)
    assert is_nil(snapshot.course_handicap_rounded)
    assert competition_count(setup.entry.id) == 0
  end

  test "RESTRICT foreign keys preserve handicap history" do
    setup = setup_round_with_tees!(assign_tee: true)

    assert {:ok, _} =
             Scoring.confirm_handicap_input(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               %{source_handicap_index: D.new("5.0")}
             )

    assert_raise Postgrex.Error, fn ->
      Repo.query!("DELETE FROM round_entries WHERE id = $1::uuid", [
        Ecto.UUID.dump!(setup.entry.id)
      ])
    end
  end

  defp build_built_snapshot!(setup) do
    assert {:ok, _} =
             Scoring.confirm_handicap_input(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.entry.id,
               %{source_handicap_index: D.new("10.0")}
             )

    assert {:ok, _} =
             Scoring.build_handicap_snapshot(setup.entry.id, %{
               course_handicap_unrounded: D.new("11.0"),
               course_handicap_rounded: 11
             })
  end

  defp fetch_snapshot!(entry_id) do
    HandicapSnapshot
    |> Ash.Query.filter(round_entry_id == ^entry_id)
    |> Ash.read_one!(authorize?: false)
  end

  defp competition_count(entry_id) do
    [[count]] =
      Repo.query!("SELECT count(*) FROM competition_handicaps WHERE round_entry_id = $1::uuid", [
        Ecto.UUID.dump!(entry_id)
      ]).rows

    count
  end

  defp audit_count do
    [[count]] = Repo.query!("SELECT count(*) FROM audit_events").rows
    count
  end

  defp setup_round_with_tees!(opts \\ []) do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    white = create_tee_set!(event, admin, course, "White")
    red = create_tee_set!(event, admin, course, "Red")
    profile_a = create_profile!(event, admin, white, holes, "Men", par: 4, slope: 120)
    profile_b = create_profile!(event, admin, red, holes, "Women", par: 5, slope: 125)

    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes, & &1.id))

    profile_ids =
      if Keyword.get(opts, :profiles, 1) > 1,
        do: [profile_a.id, profile_b.id],
        else: [profile_a.id]

    {:ok, snapshots} = SnapshotRoundTeeProfiles.run(admin, round.id, profile_ids)
    tee_a = Enum.find(snapshots, &(&1.source_tee_rating_profile_id == profile_a.id))
    assert tee_a.round_id == round.id

    tee_b =
      if Keyword.get(opts, :profiles, 1) > 1 do
        Enum.find(snapshots, &(&1.source_tee_rating_profile_id == profile_b.id))
      end

    ctx = %{event: event, round: round, admin: admin}

    entries =
      for _ <- 1..Keyword.get(opts, :entries, 1) do
        add_entry!(ctx)
      end

    entry = hd(entries)

    if Keyword.get(opts, :assign_tee) do
      assert {:ok, _} =
               Competition.assign_round_tee(
                 admin,
                 event.id,
                 round.id,
                 entry.id,
                 tee_a.id
               )
    end

    competition =
      if Keyword.get(opts, :competition) do
        {:ok, competition} =
          ConfigureRoundCompetition.run(admin, event.id, round.id, %{
            handicap_allowance_percent: 85
          })

        competition
      end

    %{
      event: event,
      round: round,
      admin: admin,
      entry: entry,
      entries: entries,
      tee_a: tee_a,
      tee_b: tee_b,
      competition: competition
    }
  end

  defp add_entry!(%{event: event, round: round, admin: admin}) do
    player = create_player!()

    {:ok, entry} =
      Competition.add_round_entry(event.id, round.id, player.id, actor: admin)

    entry
  end

  defp force_participation!(round_entry_id, status) do
    Repo.query!(
      "UPDATE round_entries SET participation_status = $1 WHERE id = $2::uuid",
      [Atom.to_string(status), Ecto.UUID.dump!(round_entry_id)]
    )
  end

  defp set_round_state!(round, state) do
    Repo.query!("UPDATE rounds SET state = $1 WHERE id = $2::uuid", [
      Atom.to_string(state),
      Ecto.UUID.dump!(round.id)
    ])

    Repo.get!(Round, round.id)
  end

  defp assign_role!(actor, event, staff, role) do
    {:ok, _} =
      Accounts.assign_event_staff_role(
        %{event_id: event.id, staff_user_id: staff.id, role: role},
        actor: actor
      )
  end

  defp create_player!(attrs \\ %{}) do
    defaults = %{
      first_name: "Pat",
      surname: "Golfer#{System.unique_integer([:positive])}"
    }

    Player
    |> Ash.Changeset.for_create(:create_internal, Map.merge(defaults, attrs))
    |> Ash.create!(authorize?: false)
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
    email = "#{Process.get(:gls22_prefix)}-#{System.unique_integer([:positive])}@example.com"

    Accounts.StaffUser
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
        %{name: "Test Course #{suffix}", location: "Here"},
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
end
