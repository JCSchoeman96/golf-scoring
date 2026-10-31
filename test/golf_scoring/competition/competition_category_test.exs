defmodule GolfScoring.Competition.CompetitionCategoryTest do
  use ExUnit.Case, async: false

  alias Ash.Resource.Info
  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Accounts.EventStaffAssignment
  alias GolfScoring.Competition
  alias GolfScoring.Competition.CompetitionCategory
  alias GolfScoring.Competition.Event
  alias GolfScoring.Competition.Round
  alias GolfScoring.Competition.RoundEntryCategoryMembership
  alias GolfScoring.Competition.Services.AssignRoundEntryCategories
  alias GolfScoring.Repo

  @password "GLS-17 synthetic staff passphrase 2026"
  @unique_membership_constraint "round_entry_category_memberships_unique_index"
  @membership_category_fkey "round_entry_category_memberships_competition_category_id_fkey"
  @membership_entry_fkey "round_entry_category_memberships_round_entry_id_fkey"

  setup do
    Process.put(:gls17_email_prefix, "gls17-#{Ecto.UUID.generate()}")
    on_exit(fn -> Process.delete(:gls17_email_prefix) end)

    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  test "assign_round_entry_categories assigns multiple overlapping categories" do
    %{event: event, round: round, admin: admin, entry: entry} = setup_entry!()
    senior = create_category!(round, "Senior")
    women = create_category!(round, "Women")

    assert {:ok, %{memberships: memberships}} =
             AssignRoundEntryCategories.run(
               admin,
               event.id,
               round.id,
               entry.id,
               [senior.id, women.id]
             )

    assert length(memberships) == 2
    assert Enum.sort(category_ids(memberships)) == Enum.sort([senior.id, women.id])
  end

  test "CompetitionCategory and membership resources avoid generic public CRUD" do
    assert CompetitionCategory in Ash.Domain.Info.resources(Competition)
    assert RoundEntryCategoryMembership in Ash.Domain.Info.resources(Competition)
    assert Info.action(CompetitionCategory, :create_internal)
    refute Info.action(CompetitionCategory, :create)
    refute Info.action(CompetitionCategory, :update)
    refute Info.action(CompetitionCategory, :destroy)
    refute Info.action(RoundEntryCategoryMembership, :create)
    refute Info.action(RoundEntryCategoryMembership, :update)
    refute Info.action(RoundEntryCategoryMembership, :destroy)
    refute function_exported?(Competition, :create_competition_category, 2)

    category_attr_names =
      CompetitionCategory
      |> Ash.Resource.Info.attributes()
      |> Enum.map(& &1.name)

    refute :status in category_attr_names
    refute :active in category_attr_names
  end

  test "assign coordinator uses private internal Ash membership actions only" do
    assert Info.action(RoundEntryCategoryMembership, :create_internal)
    assert Info.action(RoundEntryCategoryMembership, :destroy_internal)

    source = File.read!("lib/golf_scoring/competition/services/assign_round_entry_categories.ex")

    refute source =~ "gls17_skip"
    refute source =~ "INSERT INTO round_entry_category_memberships"
    refute source =~ "DELETE FROM round_entry_category_memberships"
  end

  test "PostgreSQL enforces unique membership and same-round integrity with RESTRICT" do
    %{event: event, round: round, admin: admin, entry: entry} = setup_entry!()
    category = create_category!(round, "Open Men")

    assert {:ok, _} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [category.id])

    duplicate_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO round_entry_category_memberships
            (round_id, round_entry_id, competition_category_id)
          VALUES ($1::uuid, $2::uuid, $3::uuid)
          """,
          [
            Ecto.UUID.dump!(round.id),
            Ecto.UUID.dump!(entry.id),
            Ecto.UUID.dump!(category.id)
          ]
        )
      end

    assert duplicate_error.postgres.code == :unique_violation
    assert duplicate_error.postgres.constraint == @unique_membership_constraint

    other_event = create_event!()
    other_admin = create_event_admin!(other_event)
    other_course = create_course!(other_event, other_admin)

    {:ok, other_round} =
      Competition.create_round(other_event.id, other_course.id, actor: other_admin)

    other_entry =
      create_player!()
      |> then(fn player ->
        {:ok, e} =
          Competition.add_round_entry(other_event.id, other_round.id, player.id,
            actor: other_admin
          )

        e
      end)

    other_category = create_category!(other_round, "Other Round")

    cross_round_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO round_entry_category_memberships
            (round_id, round_entry_id, competition_category_id)
          VALUES ($1::uuid, $2::uuid, $3::uuid)
          """,
          [
            Ecto.UUID.dump!(round.id),
            Ecto.UUID.dump!(entry.id),
            Ecto.UUID.dump!(other_category.id)
          ]
        )
      end

    assert cross_round_error.postgres.code == :foreign_key_violation
    assert cross_round_error.postgres.constraint == @membership_category_fkey

    cross_entry_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO round_entry_category_memberships
            (round_id, round_entry_id, competition_category_id)
          VALUES ($1::uuid, $2::uuid, $3::uuid)
          """,
          [
            Ecto.UUID.dump!(other_round.id),
            Ecto.UUID.dump!(other_entry.id),
            Ecto.UUID.dump!(category.id)
          ]
        )
      end

    assert cross_entry_error.postgres.code == :foreign_key_violation

    assert cross_entry_error.postgres.constraint in [
             @membership_entry_fkey,
             @membership_category_fkey
           ]

    assert %Postgrex.Result{rows: [["r"]]} =
             Repo.query!("""
             SELECT c.confdeltype::text
             FROM pg_constraint c
             WHERE c.conrelid = 'round_entry_category_memberships'::regclass
               AND c.contype = 'f'
               AND c.conname = 'round_entry_category_memberships_round_id_fkey'
             """)
  end

  test "assign_round_entry_categories replaces the full category set" do
    %{event: event, round: round, admin: admin, entry: entry} = setup_entry!()
    a = create_category!(round, "A")
    b = create_category!(round, "B")
    c = create_category!(round, "C")

    assert {:ok, _} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [a.id, b.id])

    assert {:ok, %{memberships: second}} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [b.id, c.id])

    assert Enum.sort(category_ids(second)) == Enum.sort([b.id, c.id])
    assert membership_count(entry.id) == 2
  end

  test "assign_round_entry_categories clears all memberships with an empty set pre-open" do
    %{event: event, round: round, admin: admin, entry: entry} = setup_entry!()
    category = create_category!(round, "Senior")

    assert {:ok, _} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [category.id])

    assert {:ok, %{memberships: []}} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [])

    assert membership_count(entry.id) == 0
  end

  test "assigning the same logical category set twice is idempotent" do
    %{event: event, round: round, admin: admin, entry: entry} = setup_entry!()
    senior = create_category!(round, "Senior")
    women = create_category!(round, "Women")
    ids = [senior.id, women.id]

    assert {:ok, _} = AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, ids)
    assert {:ok, _} = AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, ids)

    assert membership_count(entry.id) == 2
    assert Enum.sort(list_membership_category_ids(entry.id)) == Enum.sort(ids)
  end

  test "assign_round_entry_categories authorization matrix and pre-open round states" do
    %{event: event, round: round, admin: admin, entry: entry} = setup_entry!()
    manager = create_staff_user!()
    assign_role!(admin, event, manager, :competition_manager)
    staff = create_staff_user!()
    assign_role!(admin, event, staff, :registration_staff)
    scoring_support = create_staff_user!()
    assign_role!(admin, event, scoring_support, :scoring_support)
    system_admin = create_system_admin!()
    category = create_category!(round, "Open")

    assert {:ok, _} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [category.id])

    entry2_player = create_player!()

    assert {:ok, entry2} =
             Competition.add_round_entry(event.id, round.id, entry2_player.id, actor: admin)

    assert {:ok, _} =
             AssignRoundEntryCategories.run(manager, event.id, round.id, entry2.id, [category.id])

    entry3_player = create_player!()

    assert {:ok, entry3} =
             Competition.add_round_entry(event.id, round.id, entry3_player.id, actor: admin)

    assert {:error, :forbidden} =
             AssignRoundEntryCategories.run(staff, event.id, round.id, entry3.id, [category.id])

    entry4_player = create_player!()

    assert {:ok, entry4} =
             Competition.add_round_entry(event.id, round.id, entry4_player.id, actor: admin)

    assert {:error, :forbidden} =
             AssignRoundEntryCategories.run(
               scoring_support,
               event.id,
               round.id,
               entry4.id,
               [category.id]
             )

    entry5_player = create_player!()

    assert {:ok, entry5} =
             Competition.add_round_entry(event.id, round.id, entry5_player.id, actor: admin)

    assert {:error, :forbidden} =
             AssignRoundEntryCategories.run(system_admin, event.id, round.id, entry5.id, [
               category.id
             ])

    ready_round = set_round_state!(round, :ready)
    entry6_player = create_player!()

    assert {:ok, entry6} =
             Competition.add_round_entry(event.id, ready_round.id, entry6_player.id, actor: admin)

    assert {:ok, _} =
             AssignRoundEntryCategories.run(admin, event.id, ready_round.id, entry6.id, [
               category.id
             ])

    locked_entry_player = create_player!()

    assert {:ok, locked_entry} =
             Competition.add_round_entry(event.id, ready_round.id, locked_entry_player.id,
               actor: admin
             )

    for {state, label} <- [
          {:scoring_open, "scoring_open"},
          {:scoring_closed, "scoring_closed"},
          {:finalized, "finalized"},
          {:cancelled, "cancelled"}
        ] do
      locked = set_round_state!(ready_round, state)

      assert {:error, {:invalid_round_state, ^label}} =
               AssignRoundEntryCategories.run(admin, event.id, locked.id, locked_entry.id, [
                 category.id
               ])
    end
  end

  test "stale Event Admin and Competition Manager cannot assign categories" do
    %{event: event, round: round, admin: admin, entry: entry} = setup_entry!()
    manager = create_staff_user!()
    assign_role!(admin, event, manager, :competition_manager)
    category = create_category!(round, "Senior")
    stale_admin = admin
    stale_manager = manager
    replacement = create_event_admin!(event)

    assert {:ok, _} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [category.id])

    assert {:ok, _revoked} =
             Accounts.revoke_event_staff_role(active_assignment_record(event, admin),
               actor: replacement
             )

    assert {:error, :forbidden} =
             AssignRoundEntryCategories.run(stale_admin, event.id, round.id, entry.id, [])

    assert membership_count(entry.id) == 1

    assert {:ok, _revoked_manager} =
             Accounts.revoke_event_staff_role(
               active_assignment_record(event, manager, :competition_manager),
               actor: replacement
             )

    assert {:error, :forbidden} =
             AssignRoundEntryCategories.run(stale_manager, event.id, round.id, entry.id, [])

    assert membership_count(entry.id) == 1
  end

  test "cross-round category ids fail without mutating prior memberships" do
    %{event: event, round: round, admin: admin, entry: entry} = setup_entry!()
    local = create_category!(round, "Local")

    assert {:ok, _} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [local.id])

    other_event = create_event!()
    other_admin = create_event_admin!(other_event)
    other_course = create_course!(other_event, other_admin)

    {:ok, other_round} =
      Competition.create_round(other_event.id, other_course.id, actor: other_admin)

    foreign = create_category!(other_round, "Foreign")

    assert {:error, :missing_category} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [
               local.id,
               foreign.id
             ])

    assert list_membership_category_ids(entry.id) == [local.id]
  end

  test "missing category id fails atomically and preserves prior memberships" do
    %{event: event, round: round, admin: admin, entry: entry} = setup_entry!()
    kept = create_category!(round, "Kept")

    assert {:ok, _} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [kept.id])

    assert {:error, :missing_category} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [
               kept.id,
               Ecto.UUID.generate()
             ])

    assert list_membership_category_ids(entry.id) == [kept.id]
  end

  test "assign_round_entry_categories rolls back when a membership insert fails" do
    %{event: event, round: round, admin: admin, entry: entry} = setup_entry!()
    a = create_category!(round, "A")
    b = create_category!(round, "B")
    c = create_category!(round, "C")

    assert {:ok, _} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [a.id, b.id])

    install_membership_insert_failure_trigger!()

    assert {:error, _reason} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [b.id, c.id])

    assert Enum.sort(list_membership_category_ids(entry.id)) == Enum.sort([a.id, b.id])

    drop_membership_insert_failure_trigger!()
  end

  @tag :real_concurrency
  test "independent PostgreSQL backends serialize concurrent category replacements" do
    fixture_key = System.unique_integer([:positive])
    email_prefix = "gls17-unboxed-#{fixture_key}"

    fixture =
      Sandbox.unboxed_run(Repo, fn ->
        setup_committed_concurrency_fixture!(email_prefix)
      end)

    try do
      parent = self()
      set_bc = [fixture.b_id, fixture.c_id]
      set_cd = [fixture.c_id, fixture.d_id]

      task_bc =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            backend_pid = pg_backend_pid!()
            send(parent, {:gls17_concurrency_ready, :set_bc, backend_pid})

            receive do
              :gls17_concurrency_go ->
                AssignRoundEntryCategories.run(
                  fixture.admin,
                  fixture.event_id,
                  fixture.round_id,
                  fixture.entry_id,
                  set_bc
                )
            after
              10_000 -> flunk("GLS-17 concurrency task set_bc did not receive go signal")
            end
          end)
        end)

      task_cd =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            backend_pid = pg_backend_pid!()
            send(parent, {:gls17_concurrency_ready, :set_cd, backend_pid})

            receive do
              :gls17_concurrency_go ->
                AssignRoundEntryCategories.run(
                  fixture.admin,
                  fixture.event_id,
                  fixture.round_id,
                  fixture.entry_id,
                  set_cd
                )
            after
              10_000 -> flunk("GLS-17 concurrency task set_cd did not receive go signal")
            end
          end)
        end)

      assert_receive {:gls17_concurrency_ready, :set_bc, backend_pid_bc}, 10_000
      assert_receive {:gls17_concurrency_ready, :set_cd, backend_pid_cd}, 10_000
      assert backend_pid_bc != backend_pid_cd

      send(task_bc.pid, :gls17_concurrency_go)
      send(task_cd.pid, :gls17_concurrency_go)

      assert {:ok, _} = Task.await(task_bc, 30_000)
      assert {:ok, _} = Task.await(task_cd, 30_000)

      final_ids =
        Sandbox.unboxed_run(Repo, fn ->
          list_membership_category_ids(fixture.entry_id)
        end)

      sorted_final = Enum.sort(final_ids)
      allowed = [Enum.sort(set_bc), Enum.sort(set_cd)]

      assert length(final_ids) == 2
      assert sorted_final in allowed
      refute sorted_final == Enum.sort([fixture.a_id, fixture.b_id, fixture.c_id])
      refute sorted_final == Enum.sort([fixture.b_id, fixture.c_id, fixture.d_id])
      refute final_ids == []
    after
      cleanup_committed_concurrency_fixture!(fixture)
    end
  end

  test "category assignment does not mutate RoundEntry identity or registration fields" do
    %{event: event, round: round, admin: admin, entry: entry} = setup_entry!()
    category = create_category!(round, "Senior")

    before =
      Repo.query!(
        """
        SELECT player_id::text, registration_status, participation_status,
               checked_in_at, checked_in_by_staff_user_id::text
        FROM round_entries WHERE id = $1::uuid
        """,
        [Ecto.UUID.dump!(entry.id)]
      ).rows

    assert {:ok, _} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [category.id])

    after_rows =
      Repo.query!(
        """
        SELECT player_id::text, registration_status, participation_status,
               checked_in_at, checked_in_by_staff_user_id::text
        FROM round_entries WHERE id = $1::uuid
        """,
        [Ecto.UUID.dump!(entry.id)]
      ).rows

    assert before == after_rows
  end

  defp setup_entry! do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)
    player = create_player!()

    {:ok, entry} =
      Competition.add_round_entry(event.id, round.id, player.id, actor: admin)

    %{event: event, round: round, admin: admin, entry: entry}
  end

  defp create_category!(round, name) do
    CompetitionCategory
    |> Ash.Changeset.for_create(:create_internal, %{round_id: round.id, name: name})
    |> Ash.create!(authorize?: false)
  end

  defp create_player! do
    GolfScoring.Competition.Player
    |> Ash.Changeset.for_create(:create_internal, %{
      first_name: "Pat",
      surname: "Golfer#{System.unique_integer([:positive])}"
    })
    |> Ash.create!(authorize?: false)
  end

  defp category_ids(memberships), do: Enum.map(memberships, & &1.competition_category_id)

  defp membership_count(round_entry_id) do
    [[count]] =
      Repo.query!(
        "SELECT count(*) FROM round_entry_category_memberships WHERE round_entry_id = $1::uuid",
        [Ecto.UUID.dump!(round_entry_id)]
      ).rows

    count
  end

  defp list_membership_category_ids(round_entry_id) do
    Repo.query!(
      """
      SELECT competition_category_id::text
      FROM round_entry_category_memberships
      WHERE round_entry_id = $1::uuid
      ORDER BY competition_category_id
      """,
      [Ecto.UUID.dump!(round_entry_id)]
    ).rows
    |> Enum.map(fn [id] -> Ecto.UUID.cast!(id) end)
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

  defp active_assignment_record(event, staff, role \\ :event_admin) do
    [[assignment_id]] =
      Repo.query!(
        "SELECT id::text FROM event_staff_assignments WHERE event_id = $1::uuid AND staff_user_id = $2::uuid AND role = $3 AND status = 'active'",
        [
          Ecto.UUID.dump!(event.id),
          Ecto.UUID.dump!(staff.id),
          Atom.to_string(role)
        ]
      ).rows

    EventStaffAssignment
    |> Ash.get!(assignment_id, authorize?: false)
  end

  defp install_membership_insert_failure_trigger! do
    Repo.query!("""
    CREATE FUNCTION gls17_reject_membership_insert() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'simulated GLS-17 membership insert failure';
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER gls17_reject_membership_insert
    BEFORE INSERT ON round_entry_category_memberships
    FOR EACH ROW EXECUTE FUNCTION gls17_reject_membership_insert()
    """)
  end

  defp drop_membership_insert_failure_trigger! do
    Repo.query!("DROP TRIGGER gls17_reject_membership_insert ON round_entry_category_memberships")
    Repo.query!("DROP FUNCTION gls17_reject_membership_insert()")
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
    email =
      "#{Process.get(:gls17_email_prefix)}-#{System.unique_integer([:positive])}@example.com"

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
      GolfScoring.GolfCatalog.create_course(
        event.id,
        %{name: "Test Course #{suffix}", location: "Here"},
        actor: admin
      )

    course
  end

  defp setup_committed_concurrency_fixture!(email_prefix) do
    event = create_event!()
    admin = create_staff_user_for_prefix!(email_prefix)

    Repo.query!(
      "INSERT INTO event_staff_assignments (event_id, staff_user_id, role, status) VALUES ($1::uuid, $2::uuid, 'event_admin', 'active')",
      [Ecto.UUID.dump!(event.id), Ecto.UUID.dump!(admin.id)]
    )

    course = create_course!(event, admin, "Unboxed#{System.unique_integer([:positive])}")
    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)

    player =
      GolfScoring.Competition.Player
      |> Ash.Changeset.for_create(:create_internal, %{
        first_name: "Pat",
        surname: "Unboxed#{System.unique_integer([:positive])}"
      })
      |> Ash.create!(authorize?: false)

    {:ok, entry} =
      Competition.add_round_entry(event.id, round.id, player.id, actor: admin)

    a = create_category!(round, "A")
    b = create_category!(round, "B")
    c = create_category!(round, "C")
    d = create_category!(round, "D")

    assert {:ok, _} =
             AssignRoundEntryCategories.run(admin, event.id, round.id, entry.id, [a.id])

    %{
      event_id: event.id,
      round_id: round.id,
      entry_id: entry.id,
      player_id: player.id,
      course_id: course.id,
      staff_id: admin.id,
      admin: admin,
      a_id: a.id,
      b_id: b.id,
      c_id: c.id,
      d_id: d.id
    }
  end

  defp create_staff_user_for_prefix!(email_prefix) do
    email = "#{email_prefix}-#{System.unique_integer([:positive])}@example.com"

    Accounts.StaffUser
    |> Ash.Changeset.for_create(:provision_staff_user, %{
      email: email,
      password: @password,
      password_confirmation: @password
    })
    |> Ash.create!(authorize?: false)
  end

  defp pg_backend_pid! do
    Repo.query!("SELECT pg_backend_pid()").rows |> hd() |> hd()
  end

  defp cleanup_committed_concurrency_fixture!(fixture) do
    Sandbox.unboxed_run(Repo, fn ->
      dumped_event = Ecto.UUID.dump!(fixture.event_id)
      dumped_round = Ecto.UUID.dump!(fixture.round_id)
      dumped_entry = Ecto.UUID.dump!(fixture.entry_id)
      dumped_player = Ecto.UUID.dump!(fixture.player_id)
      dumped_course = Ecto.UUID.dump!(fixture.course_id)
      dumped_staff = Ecto.UUID.dump!(fixture.staff_id)

      Repo.query!(
        "DELETE FROM round_entry_category_memberships WHERE round_entry_id = $1::uuid",
        [dumped_entry]
      )

      Repo.query!("DELETE FROM competition_categories WHERE round_id = $1::uuid", [dumped_round])
      Repo.query!("DELETE FROM round_entries WHERE id = $1::uuid", [dumped_entry])
      Repo.query!("DELETE FROM round_holes WHERE round_id = $1::uuid", [dumped_round])
      Repo.query!("DELETE FROM rounds WHERE id = $1::uuid", [dumped_round])
      Repo.query!("DELETE FROM players WHERE id = $1::uuid", [dumped_player])
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
end
