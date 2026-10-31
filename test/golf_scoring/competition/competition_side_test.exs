defmodule GolfScoring.Competition.CompetitionSideTest do
  use ExUnit.Case, async: false

  require Ash.Query

  alias Ash.Changeset
  alias Ash.Resource.Info
  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Competition
  alias GolfScoring.Competition.CompetitionSide
  alias GolfScoring.Competition.CompetitionSideMembership
  alias GolfScoring.Competition.CompetitionSideResult
  alias GolfScoring.Competition.Event
  alias GolfScoring.Competition.RoundCompetition
  alias GolfScoring.Competition.Services.AssignEntryToGroup
  alias GolfScoring.Competition.Services.ConfigureRoundCompetition
  alias GolfScoring.Competition.Services.CreateCompetitionSide
  alias GolfScoring.Competition.Services.ReplaceRoundEntry
  alias GolfScoring.Competition.Services.SetSideMembership
  alias GolfScoring.Competition.FourBallStablefordV1SidePolicy
  alias GolfScoring.Competition.StartingParticipant
  alias GolfScoring.Repo

  @password "GLS-19 synthetic staff passphrase 2026"
  @membership_unique "competition_side_memberships_unique_entry_per_competition_index"
  @side_result_unique "competition_side_results_unique_side_index"
  @side_result_state_check "competition_side_results_state_must_be_valid"

  setup do
    Process.put(:gls19_email_prefix, "gls19-#{Ecto.UUID.generate()}")
    on_exit(fn -> Process.delete(:gls19_email_prefix) end)

    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  test "competition side resources are registered without generic public CRUD" do
    assert RoundCompetition in Ash.Domain.Info.resources(Competition)
    assert CompetitionSide in Ash.Domain.Info.resources(Competition)
    assert CompetitionSideMembership in Ash.Domain.Info.resources(Competition)
    assert CompetitionSideResult in Ash.Domain.Info.resources(Competition)

    refute Info.action(CompetitionSide, :create)
    refute Info.action(CompetitionSideMembership, :create)
    assert function_exported?(Competition, :set_side_membership, 6)
  end

  test "PostgreSQL enforces membership uniqueness and side result uniqueness" do
    setup = setup_round_with_competition!(solo_permitted: true)
    side = create_side!(setup, :partnership)
    entry_a = add_entry!(setup)
    entry_b = add_entry!(setup)

    assert {:ok, _} =
             SetSideMembership.run(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.competition.id,
               side.id,
               [entry_a.id, entry_b.id]
             )

    duplicate =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO competition_side_memberships
            (id, round_competition_id, competition_side_id, round_entry_id, round_id, inserted_at, updated_at)
          VALUES
            (gen_random_uuid(), $1::uuid, $2::uuid, $3::uuid, $4::uuid, now(), now())
          """,
          [
            Ecto.UUID.dump!(setup.competition.id),
            Ecto.UUID.dump!(side.id),
            Ecto.UUID.dump!(entry_a.id),
            Ecto.UUID.dump!(setup.round.id)
          ]
        )
      end

    assert duplicate.postgres.code == :unique_violation
    assert duplicate.postgres.constraint == @membership_unique

    duplicate_result =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO competition_side_results
            (id, competition_side_id, state, inserted_at, updated_at)
          VALUES (gen_random_uuid(), $1::uuid, 'provisional', now(), now())
          """,
          [Ecto.UUID.dump!(side.id)]
        )
      end

    assert duplicate_result.postgres.code == :unique_violation
    assert duplicate_result.postgres.constraint == @side_result_unique

    invalid_state =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          "UPDATE competition_side_results SET state = 'bogus' WHERE competition_side_id = $1::uuid",
          [Ecto.UUID.dump!(side.id)]
        )
      end

    assert invalid_state.postgres.code == :check_violation
    assert invalid_state.postgres.constraint == @side_result_state_check
  end

  test "partnership requires exactly two current starters" do
    setup = setup_round_with_competition!(solo_permitted: true)
    side = create_side!(setup, :partnership)
    one = add_entry!(setup)

    assert {:error, :invalid_side_cardinality} =
             SetSideMembership.run(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.competition.id,
               side.id,
               [one.id]
             )
  end

  test "intentional solo requires competition solo permission" do
    setup = setup_round_with_competition!(solo_permitted: false)
    side = create_side!(setup, :solo)
    one = add_entry!(setup)

    assert {:error, :solo_not_permitted} =
             SetSideMembership.run(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.competition.id,
               side.id,
               [one.id]
             )
  end

  test "valid partnership and permitted solo membership" do
    setup = setup_round_with_competition!(solo_permitted: true)
    partnership_side = create_side!(setup, :partnership)
    solo_side = create_side!(setup, :solo)
    [a, b, c] = for _ <- 1..3, do: add_entry!(setup)

    assert {:ok, _} =
             SetSideMembership.run(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.competition.id,
               partnership_side.id,
               [a.id, b.id]
             )

    assert {:ok, _} =
             SetSideMembership.run(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.competition.id,
               solo_side.id,
               [c.id]
             )
  end

  test "moving an entry to another side rejects leaving the source partnership with one current starter" do
    setup = setup_round_with_competition!(solo_permitted: true)
    side_a = create_side!(setup, :partnership)
    side_b = create_side!(setup, :partnership)
    [e1, e2, e3] = for _ <- 1..3, do: add_entry!(setup)

    assert {:ok, _} =
             SetSideMembership.run(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.competition.id,
               side_a.id,
               [e1.id, e2.id]
             )

    assert {:error, :invalid_side_cardinality} =
             SetSideMembership.run(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.competition.id,
               side_b.id,
               [e1.id, e3.id]
             )

    assert {:ok, _} =
             SetSideMembership.run(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.competition.id,
               side_a.id,
               [e2.id, add_entry!(setup).id]
             )

    assert {:ok, _} =
             SetSideMembership.run(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.competition.id,
               side_b.id,
               [e1.id, e3.id]
             )

    e1_rows =
      Repo.query!(
        "SELECT competition_side_id::text FROM competition_side_memberships WHERE round_entry_id = $1::uuid",
        [Ecto.UUID.dump!(e1.id)]
      ).rows

    assert e1_rows == [[side_b.id]]
  end

  test "PostgreSQL rejects cross-round competition side membership" do
    setup = setup_round_with_competition!(solo_permitted: true)
    side = create_side!(setup, :partnership)
    entry = add_entry!(setup)

    other_course = create_course!(setup.event, setup.admin)

    {:ok, other_round} =
      Competition.create_round(setup.event.id, other_course.id, actor: setup.admin)

    other_entry = add_entry!(%{setup | round: other_round})

    cross_round =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO competition_side_memberships
            (id, round_competition_id, competition_side_id, round_entry_id, round_id, inserted_at, updated_at)
          VALUES
            (gen_random_uuid(), $1::uuid, $2::uuid, $3::uuid, $4::uuid, now(), now())
          """,
          [
            Ecto.UUID.dump!(setup.competition.id),
            Ecto.UUID.dump!(side.id),
            Ecto.UUID.dump!(other_entry.id),
            Ecto.UUID.dump!(setup.round.id)
          ]
        )
      end

    assert cross_round.postgres.code in [:foreign_key_violation, :check_violation]

    same_round_mismatch =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO competition_side_memberships
            (id, round_competition_id, competition_side_id, round_entry_id, round_id, inserted_at, updated_at)
          VALUES
            (gen_random_uuid(), $1::uuid, $2::uuid, $3::uuid, $4::uuid, now(), now())
          """,
          [
            Ecto.UUID.dump!(setup.competition.id),
            Ecto.UUID.dump!(side.id),
            Ecto.UUID.dump!(entry.id),
            Ecto.UUID.dump!(other_round.id)
          ]
        )
      end

    assert same_round_mismatch.postgres.code in [:foreign_key_violation, :check_violation]
  end

  test "future CompetitionSideResult transitions fail closed" do
    setup = setup_round_with_competition!(solo_permitted: true)
    side = create_side!(setup, :partnership)

    [result] =
      CompetitionSideResult
      |> Ash.Query.filter(competition_side_id == ^side.id)
      |> Ash.read!(authorize?: false)

    assert result.state == :provisional

    assert {:error, %Ash.Error.Invalid{}} =
             result
             |> Changeset.for_update(:mark_ready_to_finalize)
             |> Ash.update(authorize?: false)
  end

  test "side creation creates exactly one provisional CompetitionSideResult" do
    setup = setup_round_with_competition!(solo_permitted: true)
    side = create_side!(setup, :partnership)

    results =
      CompetitionSideResult
      |> Ash.Query.filter(competition_side_id == ^side.id)
      |> Ash.read!(authorize?: false)

    assert length(results) == 1
    assert hd(results).state == :provisional
  end

  test "StartingParticipant predicate is reused for side membership eligibility" do
    setup = setup_round_with_competition!(solo_permitted: true)
    side = create_side!(setup, :partnership)
    entry = add_entry!(setup)
    other = add_entry!(setup)

    assert StartingParticipant.current_starting_participant?(entry)

    {:ok, no_show} = Competition.mark_no_show(other, actor: setup.admin)

    refute StartingParticipant.current_starting_participant?(no_show)

    assert {:error, :not_current_starting_participant} =
             SetSideMembership.run(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.competition.id,
               side.id,
               [entry.id, no_show.id]
             )
  end

  test "replacement inherits side membership and preserves original history" do
    setup = setup_round_with_competition!(solo_permitted: true)

    {:ok, group} =
      Competition.create_playing_group(setup.event.id, setup.round.id, actor: setup.admin)

    side = create_side!(setup, :partnership)
    [e1, e2] = for _ <- 1..2, do: add_entry!(setup)

    for entry <- [e1, e2] do
      {:ok, _} =
        AssignEntryToGroup.run(setup.admin, setup.event.id, setup.round.id, entry.id, group.id)
    end

    assert {:ok, _} =
             SetSideMembership.run(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.competition.id,
               side.id,
               [e1.id, e2.id]
             )

    replacement_player = create_player!()

    assert {:ok, %{original: original, replacement: replacement}} =
             ReplaceRoundEntry.run(
               setup.admin,
               setup.event.id,
               setup.round.id,
               e1.id,
               replacement_player.id
             )

    assert original.registration_status == :replaced_before_start

    original_memberships =
      CompetitionSideMembership
      |> Ash.Query.filter(round_entry_id == ^original.id)
      |> Ash.read!(authorize?: false)

    assert length(original_memberships) == 1

    replacement_memberships =
      CompetitionSideMembership
      |> Ash.Query.filter(round_entry_id == ^replacement.id)
      |> Ash.read!(authorize?: false)

    assert length(replacement_memberships) == 1
    assert hd(replacement_memberships).competition_side_id == side.id
    assert replacement.playing_group_id == group.id
  end

  @tag :real_concurrency
  test "concurrent membership assignment keeps at most one side per entry per competition" do
    email_prefix = Process.get(:gls19_email_prefix)

    fixture =
      Sandbox.unboxed_run(Repo, fn ->
        setup_committed_side_race_fixture!(email_prefix)
      end)

    try do
      parent = self()

      task_one =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, {:gls19_ready, :one, pg_backend_pid!()})

            receive do
              :gls19_go ->
                SetSideMembership.run(
                  fixture.admin,
                  fixture.event_id,
                  fixture.round_id,
                  fixture.competition_id,
                  fixture.side_a_id,
                  [fixture.entry_id, fixture.partner_a_id]
                )
            after
              10_000 -> flunk("GLS-19 concurrency worker one did not receive go")
            end
          end)
        end)

      task_two =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, {:gls19_ready, :two, pg_backend_pid!()})

            receive do
              :gls19_go ->
                SetSideMembership.run(
                  fixture.admin,
                  fixture.event_id,
                  fixture.round_id,
                  fixture.competition_id,
                  fixture.side_b_id,
                  [fixture.entry_id, fixture.partner_b_id]
                )
            after
              10_000 -> flunk("GLS-19 concurrency worker two did not receive go")
            end
          end)
        end)

      assert_receive {:gls19_ready, :one, pid_one}, 10_000
      assert_receive {:gls19_ready, :two, pid_two}, 10_000
      assert pid_one != pid_two

      send(task_one.pid, :gls19_go)
      send(task_two.pid, :gls19_go)

      results = [Task.await(task_one, 30_000), Task.await(task_two, 30_000)]

      count =
        Sandbox.unboxed_run(Repo, fn ->
          Repo.query!(
            """
            SELECT count(*)::int FROM competition_side_memberships
            WHERE round_competition_id = $1::uuid AND round_entry_id = $2::uuid
            """,
            [Ecto.UUID.dump!(fixture.competition_id), Ecto.UUID.dump!(fixture.entry_id)]
          ).rows
          |> hd()
          |> hd()
        end)

      assert count == 1
      refute Enum.all?(results, &match?({:error, :membership_create_failed}, &1))

      Sandbox.unboxed_run(Repo, fn ->
        assert :ok = assert_all_sides_valid_composition!(fixture.competition_id, fixture.round_id)
      end)
    after
      cleanup_committed_side_race_fixture!(fixture)
    end
  end

  defp setup_round_with_competition!(opts) do
    event = create_event!()
    admin = create_staff_user!()

    Repo.query!(
      "INSERT INTO event_staff_assignments (event_id, staff_user_id, role, status) VALUES ($1::uuid, $2::uuid, 'event_admin', 'active')",
      [Ecto.UUID.dump!(event.id), Ecto.UUID.dump!(admin.id)]
    )

    course = create_course!(event, admin)
    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)

    solo_permitted = Keyword.get(opts, :solo_permitted, false)

    assert {:ok, competition} =
             ConfigureRoundCompetition.run(
               admin,
               event.id,
               round.id,
               %{solo_sides_permitted: solo_permitted}
             )

    %{event: event, round: round, admin: admin, competition: competition}
  end

  defp create_side!(setup, formation) do
    assert {:ok, side} =
             CreateCompetitionSide.run(
               setup.admin,
               setup.event.id,
               setup.round.id,
               setup.competition.id,
               formation
             )

    side
  end

  defp setup_committed_side_race_fixture!(email_prefix) do
    event = create_event!()
    admin = create_staff_user_for_prefix!(email_prefix)

    Repo.query!(
      "INSERT INTO event_staff_assignments (event_id, staff_user_id, role, status) VALUES ($1::uuid, $2::uuid, 'event_admin', 'active')",
      [Ecto.UUID.dump!(event.id), Ecto.UUID.dump!(admin.id)]
    )

    course = create_course!(event, admin)
    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)

    {:ok, competition} =
      ConfigureRoundCompetition.run(admin, event.id, round.id, %{solo_sides_permitted: true})

    {:ok, side_a} =
      CreateCompetitionSide.run(admin, event.id, round.id, competition.id, :partnership)

    {:ok, side_b} =
      CreateCompetitionSide.run(admin, event.id, round.id, competition.id, :partnership)

    entry = add_entry!(%{event: event, round: round, admin: admin})
    partner_a = add_entry!(%{event: event, round: round, admin: admin})
    partner_b = add_entry!(%{event: event, round: round, admin: admin})

    player_ids = [entry.player_id, partner_a.player_id, partner_b.player_id]

    %{
      event_id: event.id,
      round_id: round.id,
      course_id: course.id,
      competition_id: competition.id,
      side_a_id: side_a.id,
      side_b_id: side_b.id,
      entry_id: entry.id,
      partner_a_id: partner_a.id,
      partner_b_id: partner_b.id,
      staff_id: admin.id,
      player_ids: player_ids,
      admin: admin
    }
  end

  defp cleanup_committed_side_race_fixture!(fixture) do
    Sandbox.unboxed_run(Repo, fn ->
      dumped_round = Ecto.UUID.dump!(fixture.round_id)
      dumped_event = Ecto.UUID.dump!(fixture.event_id)
      dumped_course = Ecto.UUID.dump!(fixture.course_id)
      dumped_staff = Ecto.UUID.dump!(fixture.staff_id)

      Repo.query!("DELETE FROM competition_side_memberships WHERE round_id = $1::uuid", [
        dumped_round
      ])

      Repo.query!(
        "DELETE FROM competition_side_results WHERE competition_side_id IN (SELECT id FROM competition_sides WHERE round_id = $1::uuid)",
        [
          dumped_round
        ]
      )

      Repo.query!("DELETE FROM competition_sides WHERE round_id = $1::uuid", [dumped_round])
      Repo.query!("DELETE FROM round_competitions WHERE round_id = $1::uuid", [dumped_round])
      Repo.query!("DELETE FROM round_entries WHERE round_id = $1::uuid", [dumped_round])
      Repo.query!("DELETE FROM rounds WHERE id = $1::uuid", [dumped_round])

      for player_id <- fixture.player_ids do
        Repo.query!("DELETE FROM players WHERE id = $1::uuid", [Ecto.UUID.dump!(player_id)])
      end

      Repo.query!("DELETE FROM course_holes WHERE course_id = $1::uuid", [dumped_course])
      Repo.query!("DELETE FROM tee_sets WHERE course_id = $1::uuid", [dumped_course])
      Repo.query!("DELETE FROM courses WHERE id = $1::uuid", [dumped_course])

      Repo.query!(
        "DELETE FROM audit_events WHERE target_id = $1::uuid OR actor_staff_user_id = $2::uuid OR target_id = $2::uuid",
        [dumped_event, dumped_staff]
      )

      Repo.query!("DELETE FROM event_staff_assignments WHERE event_id = $1::uuid", [dumped_event])
      Repo.query!("DELETE FROM events WHERE id = $1::uuid", [dumped_event])
      Repo.query!("DELETE FROM staff_users WHERE id = $1::uuid", [dumped_staff])
    end)
  end

  defp pg_backend_pid! do
    Repo.query!("SELECT pg_backend_pid()").rows |> hd() |> hd()
  end

  defp assert_all_sides_valid_composition!(competition_id, round_id) do
    competition = Ash.get!(RoundCompetition, competition_id, authorize?: false)

    sides =
      CompetitionSide
      |> Ash.Query.filter(round_competition_id == ^competition_id)
      |> Ash.read!(authorize?: false)

    Enum.reduce(sides, :ok, fn side, :ok ->
      rows =
        Repo.query!(
          """
          SELECT re.id::text, re.event_id::text, re.round_id::text,
                 re.registration_status, re.participation_status
          FROM competition_side_memberships csm
          JOIN round_entries re ON re.id = csm.round_entry_id
          WHERE csm.competition_side_id = $1::uuid
            AND csm.round_id = $2::uuid
          ORDER BY re.id
          """,
          [Ecto.UUID.dump!(side.id), Ecto.UUID.dump!(round_id)]
        ).rows

      entries =
        Enum.map(rows, fn [id, eid, rid, reg, part] ->
          %{
            id: Ecto.UUID.cast!(id),
            event_id: Ecto.UUID.cast!(eid),
            round_id: Ecto.UUID.cast!(rid),
            registration_status: String.to_existing_atom(reg),
            participation_status: String.to_existing_atom(part)
          }
        end)

      FourBallStablefordV1SidePolicy.validate_side_composition(
        competition,
        side.formation,
        entries
      )
    end)
  end

  defp create_event! do
    Event
    |> Changeset.for_create(:create_internal, %{})
    |> Ash.create!(authorize?: false)
  end

  defp create_staff_user! do
    create_staff_user_for_prefix!(Process.get(:gls19_email_prefix))
  end

  defp create_staff_user_for_prefix!(prefix) do
    email = "#{prefix}-#{System.unique_integer([:positive])}@example.com"

    Accounts.StaffUser
    |> Changeset.for_create(:provision_staff_user, %{
      email: email,
      password: @password,
      password_confirmation: @password
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_course!(event, admin) do
    {:ok, course} =
      GolfScoring.GolfCatalog.create_course(
        event.id,
        %{name: "Test #{System.unique_integer([:positive])}", location: "ZA"},
        actor: admin
      )

    course
  end

  defp add_entry!(%{event: event, round: round, admin: admin}) do
    player = create_player!()

    {:ok, entry} =
      Competition.add_round_entry(event.id, round.id, player.id, actor: admin)

    entry
  end

  defp create_player! do
    GolfScoring.Competition.Player
    |> Changeset.for_create(:create_internal, %{
      first_name: "Pat",
      surname: "Golfer#{System.unique_integer([:positive])}"
    })
    |> Ash.create!(authorize?: false)
  end
end
