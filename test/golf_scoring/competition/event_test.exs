defmodule GolfScoring.Competition.EventTest do
  use ExUnit.Case, async: false

  alias Ash.Resource.Info
  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Accounts.EventStaffAssignment
  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Competition
  alias GolfScoring.Competition.Event
  alias GolfScoring.Repo

  @password "GLS-12 synthetic staff passphrase 2026"
  @event_states [:draft, :published, :live, :completed, :archived, :cancelled]
  @event_roles [:event_admin, :competition_manager, :registration_staff, :scoring_support]

  setup tags do
    Process.put(:gls12_email_prefix, "gls12-#{Ecto.UUID.generate()}")
    on_exit(fn -> Process.delete(:gls12_email_prefix) end)

    if tags[:real_concurrency] do
      :ok = Sandbox.mode(Repo, :auto)
      on_exit(fn -> Sandbox.mode(Repo, :manual) end)
    else
      owner = Sandbox.start_owner!(Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(owner) end)
    end

    :ok
  end

  test "Event is registered in Competition and persists only the approved lifecycle states" do
    assert Event in Ash.Domain.Info.resources(Competition)
    assert GolfScoring.Accounts in Application.get_env(:golf_scoring, :ash_domains)

    event = create_event!()
    assert event.state == :draft

    for state <- @event_states do
      set_event_state!(event, state)

      assert [[stored_state]] =
               Repo.query!("SELECT state FROM events WHERE id = $1::uuid", [
                 Ecto.UUID.dump!(event.id)
               ]).rows

      assert stored_state == Atom.to_string(state)
    end
  end

  test "PostgreSQL rejects an Event state outside the approved set" do
    error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!("INSERT INTO events (state) VALUES ('ready')")
      end

    assert error.postgres.code == :check_violation
    assert error.postgres.constraint == "events_state_must_be_valid"
  end

  test "archived and cancelled Events are terminal" do
    event = create_event!()
    admin = create_event_admin!(event)

    assert {:ok, cancelled} = Competition.cancel_event(event, actor: admin)
    assert cancelled.state == :cancelled

    for action <- [
          :publish_event,
          :mark_event_live,
          :complete_event,
          :archive_event,
          :cancel_event
        ] do
      assert {:error, _error} = lifecycle_update(cancelled, action, admin)
    end

    archived = set_event_state!(create_event!(), :archived)
    archived_admin = create_event_admin!(archived)

    for action <- [
          :publish_event,
          :mark_event_live,
          :complete_event,
          :archive_event,
          :cancel_event
        ] do
      assert {:error, _error} = lifecycle_update(archived, action, archived_admin)
    end

    assert event_state(archived.id) == "archived"
  end

  test "published Events can be cancelled and completed Events can be archived with audits" do
    published = set_event_state!(create_event!(), :published)
    published_admin = create_event_admin!(published)

    assert {:ok, cancelled} = Competition.cancel_event(published, actor: published_admin)
    assert cancelled.state == :cancelled
    assert [%{action: "event_cancelled"}] = lifecycle_audits(published.id)

    completed = set_event_state!(create_event!(), :completed)
    completed_admin = create_event_admin!(completed)

    assert {:ok, archived} = Competition.archive_event(completed, actor: completed_admin)
    assert archived.state == :archived
    assert [%{action: "event_archived"}] = lifecycle_audits(completed.id)
  end

  test "Event creation and lifecycle mutation stay behind named private actions" do
    assert is_nil(Info.action(Event, :create))
    assert is_nil(Info.action(Event, :update))
    assert is_nil(Info.action(Event, :destroy))
    assert is_nil(Info.action(Event, :set_state))
    assert is_nil(Info.action(Event, :transition_to))
    assert refute_exported?(Competition, :create_event)

    create_action = Info.action(Event, :create_internal)
    refute create_action.public?
    assert create_action.accept == []

    for action_name <- [:publish_event, :mark_event_live, :complete_event] do
      action = Info.action(Event, action_name)
      refute action.public?
      assert action.accept == []
    end
  end

  test "publish, live, and completion transitions fail closed until their guards exist" do
    event = create_event!()
    admin = create_event_admin!(event)

    for {action, state} <- [
          {:publish_event, :draft},
          {:mark_event_live, :published},
          {:complete_event, :live}
        ] do
      current = set_event_state!(event, state)
      assert {:error, _error} = lifecycle_update(current, action, admin)
      assert event_state(event.id) == Atom.to_string(state)
    end

    assert lifecycle_audits(event.id) == []
  end

  test "active EventAdmin can cancel an allowed lifecycle state and writes one audit" do
    event = create_event!()
    admin = create_event_admin!(event)

    assert {:ok, cancelled} = Competition.cancel_event(event, actor: admin)
    assert cancelled.state == :cancelled
    assert [audit] = event_audits(event.id)
    assert audit.action == "event_cancelled"
    assert audit.actor_staff_user_id == admin.id
    assert audit.target_type == "event"
    assert audit.target_id == event.id
    assert audit.changes["state"] == %{"from" => "draft", "to" => "cancelled"}
  end

  test "all exact EventStaff roles are accepted with active-only duplicate protection and history" do
    event = create_event!()
    admin = create_event_admin!(event)
    staff = create_staff_user!()

    assignments =
      Enum.map(@event_roles, fn role ->
        assert {:ok, assignment} = assign_role(admin, event, staff, role)
        assert assignment.role == role
        assert assignment.status == :active
        assignment
      end)

    assert Enum.map(assignments, & &1.role) == @event_roles

    assert {:error, _error} = assign_role(admin, event, staff, :competition_manager)
    assert assignment_count(event.id, staff.id, :competition_manager, :active) == 1

    manager_assignment = Enum.find(assignments, &(&1.role == :registration_staff))
    assert {:ok, revoked} = Accounts.revoke_event_staff_role(manager_assignment, actor: admin)
    assert revoked.status == :revoked
    assert {:error, _error} = Accounts.revoke_event_staff_role(revoked, actor: admin)

    assert {:ok, replacement} = assign_role(admin, event, staff, :registration_staff)
    assert replacement.id != revoked.id
    assert assignment_count(event.id, staff.id, :registration_staff, :revoked) == 1
    assert assignment_count(event.id, staff.id, :registration_staff, :active) == 1

    assert is_nil(Info.action(EventStaffAssignment, :create))
    assert is_nil(Info.action(EventStaffAssignment, :update))
    assert is_nil(Info.action(EventStaffAssignment, :destroy))
    assert is_nil(Info.action(EventStaffAssignment, :set_status))
    assert is_nil(Info.action(EventStaffAssignment, :reactivate_assignment))
  end

  test "PostgreSQL rejects invalid assignment roles and prevents duplicate active roles" do
    event = create_event!()
    admin = create_event_admin!(event)
    staff = create_staff_user!()

    assert {:ok, _assignment} = assign_role(admin, event, staff, :scoring_support)

    invalid_role_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          "INSERT INTO event_staff_assignments (event_id, staff_user_id, role) VALUES ($1::uuid, $2::uuid, 'marshal')",
          [Ecto.UUID.dump!(event.id), Ecto.UUID.dump!(staff.id)]
        )
      end

    assert invalid_role_error.postgres.code == :check_violation
    assert invalid_role_error.postgres.constraint == "event_staff_assignments_role_must_be_valid"

    duplicate_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          "INSERT INTO event_staff_assignments (event_id, staff_user_id, role) VALUES ($1::uuid, $2::uuid, 'scoring_support')",
          [Ecto.UUID.dump!(event.id), Ecto.UUID.dump!(staff.id)]
        )
      end

    assert duplicate_error.postgres.code == :unique_violation
    assert assignment_count(event.id, staff.id, :scoring_support, :active) == 1

    invalid_status_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          "INSERT INTO event_staff_assignments (event_id, staff_user_id, role, status) VALUES ($1::uuid, $2::uuid, 'registration_staff', 'restored')",
          [Ecto.UUID.dump!(event.id), Ecto.UUID.dump!(staff.id)]
        )
      end

    assert invalid_status_error.postgres.code == :check_violation

    assert invalid_status_error.postgres.constraint ==
             "event_staff_assignments_status_must_be_valid"

    assert %Postgrex.Result{rows: required_columns} =
             Repo.query!(
               "SELECT column_name, is_nullable FROM information_schema.columns WHERE table_name = 'event_staff_assignments' AND column_name IN ('event_id', 'staff_user_id', 'role', 'status') ORDER BY column_name"
             )

    assert required_columns == [
             ["event_id", "NO"],
             ["role", "NO"],
             ["staff_user_id", "NO"],
             ["status", "NO"]
           ]

    assert %Postgrex.Result{rows: index_rows} =
             Repo.query!(
               "SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'event_staff_assignments'"
             )

    indexes = Enum.map(index_rows, &hd/1)

    active_role_index =
      Enum.find(indexes, &String.contains?(&1, "event_staff_assignments_active_role_index"))

    active_event_role_index =
      Enum.find(indexes, &String.contains?(&1, "event_staff_assignments_active_event_role_index"))

    staff_index =
      Enum.find(indexes, &String.contains?(&1, "event_staff_assignments_staff_user_id_index"))

    assert active_role_index =~ "CREATE UNIQUE INDEX"
    assert active_role_index =~ "(event_id, staff_user_id, role)"
    assert active_role_index =~ "WHERE"
    assert active_event_role_index =~ "(event_id, role)"
    assert active_event_role_index =~ "WHERE"
    assert staff_index =~ "(staff_user_id)"
  end

  test "only an active EventAdmin for the same Event may assign event roles" do
    event = create_event!()
    other_event = create_event!()
    admin = create_event_admin!(event)
    target = create_staff_user!()

    assert {:ok, assignment} = assign_role(admin, event, target, :competition_manager)
    assert assignment.staff_user_id == target.id

    manager = create_staff_user!()
    assert {:ok, _manager_role} = assign_role(admin, event, manager, :competition_manager)
    assert {:error, _error} = assign_role(manager, event, create_staff_user!(), :scoring_support)

    system_admin = create_system_admin!()

    assert {:error, _error} =
             assign_role(system_admin, event, create_staff_user!(), :scoring_support)

    replacement = create_event_admin!(event)
    revoked_admin = create_staff_user!()
    {:ok, revoked_assignment} = assign_role(replacement, event, revoked_admin, :event_admin)

    assert {:ok, _revoked} =
             Accounts.revoke_event_staff_role(revoked_assignment, actor: replacement)

    assert {:error, _error} =
             assign_role(revoked_admin, event, create_staff_user!(), :scoring_support)

    cross_event_admin = create_event_admin!(other_event)

    assert {:error, _error} =
             assign_role(cross_event_admin, event, create_staff_user!(), :scoring_support)
  end

  test "suspended or disabled actors and targets cannot receive or use event authority" do
    event = create_event!()
    replacement = create_event_admin!(event)
    suspended_admin = create_staff_user!()
    disabled_admin = create_staff_user!()
    {:ok, suspended_assignment} = assign_role(replacement, event, suspended_admin, :event_admin)
    {:ok, disabled_assignment} = assign_role(replacement, event, disabled_admin, :event_admin)

    stale_suspended = set_staff_status!(suspended_admin, :suspended)
    stale_disabled = set_staff_status!(disabled_admin, :disabled)

    assert {:error, _error} =
             assign_role(stale_suspended, event, create_staff_user!(), :scoring_support)

    assert {:error, _error} =
             assign_role(stale_disabled, event, create_staff_user!(), :scoring_support)

    assert {:error, _error} = Competition.cancel_event(event, actor: stale_suspended)
    assert {:error, _error} = Competition.cancel_event(event, actor: stale_disabled)

    assert {:error, _error} =
             assign_role(
               replacement,
               event,
               set_staff_status!(create_staff_user!(), :suspended),
               :scoring_support
             )

    assert {:error, _error} =
             assign_role(
               replacement,
               event,
               set_staff_status!(create_staff_user!(), :disabled),
               :scoring_support
             )

    assert {:error, _error} =
             assign_role(replacement, event, %{id: Ecto.UUID.generate()}, :scoring_support)

    assert assignment_status(suspended_assignment.id) == "active"
    assert assignment_status(disabled_assignment.id) == "active"
  end

  test "stale actor and assignment state cannot authorize Event lifecycle operations" do
    event = create_event!()
    replacement = create_event_admin!(event)
    stale_assignment_actor = create_staff_user!()

    {:ok, actor_assignment} =
      assign_role(replacement, event, stale_assignment_actor, :event_admin)

    stale_staff_actor = create_event_admin!(event)

    assert {:ok, _revoked} =
             Accounts.revoke_event_staff_role(actor_assignment, actor: replacement)

    assert {:error, _error} = Competition.cancel_event(event, actor: stale_assignment_actor)

    stale_active_struct = stale_staff_actor
    _suspended = set_staff_status!(stale_staff_actor, :suspended)
    assert stale_active_struct.status == :active
    assert {:error, _error} = Competition.cancel_event(event, actor: stale_active_struct)

    manager = create_staff_user!()
    {:ok, _assignment} = assign_role(replacement, event, manager, :competition_manager)
    assert {:error, _error} = Competition.cancel_event(event, actor: manager)

    system_admin = create_system_admin!()
    assert {:error, _error} = Competition.cancel_event(event, actor: system_admin)

    other_event = create_event!()
    other_event_admin = create_event_admin!(other_event)
    assert {:error, _error} = Competition.cancel_event(event, actor: other_event_admin)

    assert event_state(event.id) == "draft"
    assert lifecycle_audits(event.id) == []
  end

  test "EventAdmin may revoke a non-final role but cannot remove the last effective admin" do
    event = create_event!()
    admin = create_event_admin!(event)
    target = create_staff_user!()
    {:ok, target_assignment} = assign_role(admin, event, target, :registration_staff)

    assert {:ok, revoked} = Accounts.revoke_event_staff_role(target_assignment, actor: admin)
    assert revoked.status == :revoked
    assert {:error, _error} = Accounts.revoke_event_staff_role(revoked, actor: admin)

    admin_assignment = active_assignment(event.id, admin.id, :event_admin)
    assert {:error, _error} = Accounts.revoke_event_staff_role(admin_assignment, actor: admin)
    assert assignment_status(admin_assignment.id) == "active"
    assert effective_event_admin_count(event.id) == 1
  end

  test "self-revocation is allowed when another effective EventAdmin remains" do
    event = create_event!()
    first_admin = create_event_admin!(event)
    second_admin = create_event_admin!(event)
    first_assignment = active_assignment(event.id, first_admin.id, :event_admin)
    _second_assignment = active_assignment(event.id, second_admin.id, :event_admin)

    assert effective_event_admin_count(event.id) == 2
    assert {:ok, revoked} = Accounts.revoke_event_staff_role(first_assignment, actor: first_admin)
    assert revoked.status == :revoked
    assert effective_event_admin_count(event.id) == 1
  end

  test "suspended and disabled EventAdmins do not count toward final-admin protection" do
    for inactive_status <- [:suspended, :disabled] do
      event = create_event!()
      active_admin = create_event_admin!(event)
      inactive_admin = create_event_admin!(event)
      _inactive = set_staff_status!(inactive_admin, inactive_status)
      active_assignment = active_assignment(event.id, active_admin.id, :event_admin)

      assert effective_event_admin_count(event.id) == 1

      assert {:error, _error} =
               Accounts.revoke_event_staff_role(active_assignment, actor: active_admin)

      assert assignment_status(active_assignment.id) == "active"
    end
  end

  test "assignment and revocation audits identify the actor, Event, StaffUser, role, and status" do
    event = create_event!()
    admin = create_event_admin!(event)
    staff = create_staff_user!()

    assert {:ok, assignment} = assign_role(admin, event, staff, :competition_manager)
    assert [assigned_audit] = event_audits(event.id)
    assert assigned_audit.action == "event_staff_role_assigned"
    assert assigned_audit.actor_staff_user_id == admin.id
    assert assigned_audit.context["staff_user_id"] == staff.id
    assert assigned_audit.context["role"] == "competition_manager"
    assert assigned_audit.context["assignment_id"] == assignment.id
    assert assigned_audit.changes["status"] == %{"from" => nil, "to" => "active"}

    assert {:ok, _revoked} = Accounts.revoke_event_staff_role(assignment, actor: admin)
    assert [first_audit, revoked_audit] = event_audits(event.id)
    assert first_audit.action == "event_staff_role_assigned"
    assert revoked_audit.action == "event_staff_role_revoked"
    assert revoked_audit.actor_staff_user_id == admin.id
    assert revoked_audit.context["staff_user_id"] == staff.id
    assert revoked_audit.context["role"] == "competition_manager"
    assert revoked_audit.context["assignment_id"] == assignment.id
    assert revoked_audit.changes["status"] == %{"from" => "active", "to" => "revoked"}

    assert ["event_staff_role_assigned", "event_staff_role_revoked"] ==
             Enum.map(event_audits(event.id), & &1.action)
  end

  test "failed role mutations write no success audit" do
    event = create_event!()
    admin = create_event_admin!(event)
    staff = create_staff_user!()

    assert {:error, _error} = assign_role(staff, event, create_staff_user!(), :scoring_support)
    admin_assignment = active_assignment(event.id, admin.id, :event_admin)
    assert {:error, _error} = Accounts.revoke_event_staff_role(admin_assignment, actor: admin)

    assert event_audits(event.id) == []
    refute Enum.any?(event_audits(event.id), &(&1.action == "event_staff_role_revoked"))
  end

  test "audit failure rolls assignment creation and revocation back" do
    event = create_event!()
    admin = create_event_admin!(event)
    staff = create_staff_user!()
    install_audit_failure_trigger!()

    assert {:error, _error} = assign_role(admin, event, staff, :registration_staff)
    assert assignment_count(event.id, staff.id, :registration_staff, :active) == 0
    assert event_audits(event.id) == []

    drop_audit_failure_trigger!()
    {:ok, assignment} = assign_role(admin, event, staff, :registration_staff)
    install_audit_failure_trigger!()

    assert {:error, _error} = Accounts.revoke_event_staff_role(assignment, actor: admin)
    assert assignment_status(assignment.id) == "active"
    assert Enum.count(event_audits(event.id), &(&1.action == "event_staff_role_assigned")) == 1
    refute Enum.any?(event_audits(event.id), &(&1.action == "event_staff_role_revoked"))
  end

  test "assignment foreign keys preserve Event and StaffUser history" do
    event = create_event!()
    admin = create_event_admin!(event)
    assignment = active_assignment(event.id, admin.id, :event_admin)

    for {table, id} <- [{"events", event.id}, {"staff_users", admin.id}] do
      assert_raise Postgrex.Error, fn ->
        Repo.query!("DELETE FROM #{table} WHERE id = $1::uuid", [Ecto.UUID.dump!(id)])
      end
    end

    assert assignment_status(assignment.id) == "active"
  end

  @tag :real_concurrency
  test "independent PostgreSQL sessions cannot concurrently revoke both final EventAdmins" do
    event = create_event!()
    first_admin = create_event_admin!(event)
    second_admin = create_event_admin!(event)
    first_assignment = active_assignment(event.id, first_admin.id, :event_admin)
    second_assignment = active_assignment(event.id, second_admin.id, :event_admin)
    blocker = start_event_lock_blocker(event.id)
    blocker_pid = await_blocker!(blocker, :gls12_event_lock_held)

    try do
      tasks = [
        start_independent_operation(:gls12_final_admin_one, fn ->
          Accounts.revoke_event_staff_role(first_assignment, actor: first_admin)
        end),
        start_independent_operation(:gls12_final_admin_two, fn ->
          Accounts.revoke_event_staff_role(second_assignment, actor: second_admin)
        end)
      ]

      pids = await_operation_pids([:gls12_final_admin_one, :gls12_final_admin_two])
      assert length(Enum.uniq(pids)) == 2
      refute blocker_pid in pids
      await_lock_waiters!(pids)

      send(blocker.pid, :release_gls12_lock)
      assert {:ok, :released} = Task.await(blocker, 10_000)
      results = Enum.map(tasks, &Task.await(&1, 10_000))

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, _}, &1)) == 1
      assert effective_event_admin_count_unboxed(event.id) == 1
      assert event_audit_count_unboxed(event.id, "event_staff_role_revoked") == 1
    after
      release_event_blocker(blocker)
      cleanup_committed_fixture(event.id, [first_admin.id, second_admin.id])
    end
  end

  @tag :real_concurrency
  test "independent PostgreSQL sessions create at most one duplicate active role and audit" do
    event = create_event!()
    admin = create_event_admin!(event)
    target = create_staff_user!()
    blocker = start_event_lock_blocker(event.id)
    blocker_pid = await_blocker!(blocker, :gls12_event_lock_held)

    try do
      tasks = [
        start_independent_operation(:gls12_duplicate_one, fn ->
          assign_role(admin, event, target, :registration_staff)
        end),
        start_independent_operation(:gls12_duplicate_two, fn ->
          assign_role(admin, event, target, :registration_staff)
        end)
      ]

      pids = await_operation_pids([:gls12_duplicate_one, :gls12_duplicate_two])
      assert length(Enum.uniq(pids)) == 2
      refute blocker_pid in pids
      await_lock_waiters!(pids)

      send(blocker.pid, :release_gls12_lock)
      assert {:ok, :released} = Task.await(blocker, 10_000)
      results = Enum.map(tasks, &Task.await(&1, 10_000))

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, _}, &1)) == 1
      assert assignment_count_unboxed(event.id, target.id, :registration_staff, :active) == 1
      assert event_audit_count_unboxed(event.id, "event_staff_role_assigned") == 1
    after
      release_event_blocker(blocker)
      cleanup_committed_fixture(event.id, [admin.id, target.id])
    end
  end

  @tag :real_concurrency
  test "a concurrent actor suspension is rechecked before an Event role grant commits" do
    event = create_event!()
    admin = create_event_admin!(event)
    target = create_staff_user!()
    blocker = start_staff_status_blocker(admin.id, :suspended)
    blocker_pid = await_blocker!(blocker, :gls12_staff_status_locked)

    try do
      task =
        start_independent_operation(:gls12_actor_suspend_race, fn ->
          assign_role(admin, event, target, :scoring_support)
        end)

      [operation_pid] = await_operation_pids([:gls12_actor_suspend_race])
      refute blocker_pid == operation_pid
      await_lock_waiters!([operation_pid])

      send(blocker.pid, :release_gls12_status)
      assert {:ok, :released} = Task.await(blocker, 10_000)
      assert {:error, _error} = Task.await(task, 10_000)
      assert assignment_count_unboxed(event.id, target.id, :scoring_support, :active) == 0
      assert event_audit_count_unboxed(event.id, "event_staff_role_assigned") == 0
    after
      release_status_blocker(blocker)
      cleanup_committed_fixture(event.id, [admin.id, target.id])
    end
  end

  @tag :real_concurrency
  test "a concurrent target suspension is rechecked before an Event role grant commits" do
    event = create_event!()
    admin = create_event_admin!(event)
    target = create_staff_user!()
    blocker = start_staff_status_blocker(target.id, :suspended)
    blocker_pid = await_blocker!(blocker, :gls12_staff_status_locked)

    try do
      task =
        start_independent_operation(:gls12_target_suspend_race, fn ->
          assign_role(admin, event, target, :scoring_support)
        end)

      [operation_pid] = await_operation_pids([:gls12_target_suspend_race])
      refute blocker_pid == operation_pid
      await_lock_waiters!([operation_pid])

      send(blocker.pid, :release_gls12_status)
      assert {:ok, :released} = Task.await(blocker, 10_000)
      assert {:error, _error} = Task.await(task, 10_000)
      assert assignment_count_unboxed(event.id, target.id, :scoring_support, :active) == 0
      assert event_audit_count_unboxed(event.id, "event_staff_role_assigned") == 0
    after
      release_status_blocker(blocker)
      cleanup_committed_fixture(event.id, [admin.id, target.id])
    end
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
      "#{Process.get(:gls12_email_prefix)}-#{System.unique_integer([:positive])}@example.com"

    StaffUser
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

    Repo.get!(StaffUser, staff.id)
  end

  defp assign_role(actor, event, staff, role) do
    Accounts.assign_event_staff_role(
      %{event_id: event.id, staff_user_id: staff.id, role: role},
      actor: actor
    )
  end

  defp lifecycle_update(event, action, actor) do
    event
    |> Ash.Changeset.for_update(action, %{}, actor: actor)
    |> Ash.update()
  end

  defp set_event_state!(event, state) do
    Repo.query!("UPDATE events SET state = $1 WHERE id = $2::uuid", [
      Atom.to_string(state),
      Ecto.UUID.dump!(event.id)
    ])

    Repo.get!(Event, event.id)
  end

  defp set_staff_status!(staff, status) do
    Repo.query!("UPDATE staff_users SET status = $1 WHERE id = $2::uuid", [
      Atom.to_string(status),
      Ecto.UUID.dump!(staff.id)
    ])

    Repo.get!(StaffUser, staff.id)
  end

  defp event_state(event_id) do
    [[state]] =
      Repo.query!("SELECT state FROM events WHERE id = $1::uuid", [
        Ecto.UUID.dump!(event_id)
      ]).rows

    state
  end

  defp assignment_status(assignment_id) do
    [[status]] =
      Repo.query!("SELECT status FROM event_staff_assignments WHERE id = $1::uuid", [
        Ecto.UUID.dump!(assignment_id)
      ]).rows

    status
  end

  defp assignment_count(event_id, staff_id, role, status) do
    [[count]] =
      Repo.query!(
        "SELECT count(*) FROM event_staff_assignments WHERE event_id = $1::uuid AND staff_user_id = $2::uuid AND role = $3 AND status = $4",
        [
          Ecto.UUID.dump!(event_id),
          Ecto.UUID.dump!(staff_id),
          Atom.to_string(role),
          Atom.to_string(status)
        ]
      ).rows

    count
  end

  defp active_assignment(event_id, staff_id, role) do
    [[assignment_id]] =
      Repo.query!(
        "SELECT id::text FROM event_staff_assignments WHERE event_id = $1::uuid AND staff_user_id = $2::uuid AND role = $3 AND status = 'active'",
        [Ecto.UUID.dump!(event_id), Ecto.UUID.dump!(staff_id), Atom.to_string(role)]
      ).rows

    Repo.get!(EventStaffAssignment, Ecto.UUID.cast!(assignment_id))
  end

  defp effective_event_admin_count(event_id) do
    [[count]] =
      Repo.query!(
        """
        SELECT count(*)
        FROM event_staff_assignments assignments
        JOIN staff_users staff ON staff.id = assignments.staff_user_id
        WHERE assignments.event_id = $1::uuid
          AND assignments.role = 'event_admin'
          AND assignments.status = 'active'
          AND staff.status = 'active'
        """,
        [Ecto.UUID.dump!(event_id)]
      ).rows

    count
  end

  defp event_audits(event_id) do
    Repo.query!(
      "SELECT action, actor_staff_user_id::text, target_type, target_id::text, context, changes FROM audit_events WHERE target_type = 'event' AND target_id = $1::uuid ORDER BY occurred_at, id",
      [Ecto.UUID.dump!(event_id)]
    ).rows
    |> Enum.map(fn [action, actor_id, target_type, target_id, context, changes] ->
      %{
        action: action,
        actor_staff_user_id: Ecto.UUID.cast!(actor_id),
        target_type: target_type,
        target_id: Ecto.UUID.cast!(target_id),
        context: context,
        changes: changes
      }
    end)
  end

  defp lifecycle_audits(event_id) do
    event_id
    |> event_audits()
    |> Enum.filter(
      &(&1.action in [
          "event_published",
          "event_marked_live",
          "event_completed",
          "event_archived",
          "event_cancelled"
        ])
    )
  end

  defp install_audit_failure_trigger! do
    Repo.query!("""
    CREATE FUNCTION gls12_reject_event_staff_audit() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.action IN ('event_staff_role_assigned', 'event_staff_role_revoked') THEN
        RAISE EXCEPTION 'simulated GLS-12 audit failure';
      END IF;
      RETURN NEW;
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER gls12_reject_event_staff_audit
    BEFORE INSERT ON audit_events
    FOR EACH ROW EXECUTE FUNCTION gls12_reject_event_staff_audit()
    """)
  end

  defp drop_audit_failure_trigger! do
    Repo.query!("DROP TRIGGER gls12_reject_event_staff_audit ON audit_events")
    Repo.query!("DROP FUNCTION gls12_reject_event_staff_audit()")
  end

  defp effective_event_admin_count_unboxed(event_id) do
    Sandbox.unboxed_run(Repo, fn -> effective_event_admin_count(event_id) end)
  end

  defp event_audit_count_unboxed(event_id, action) do
    Sandbox.unboxed_run(Repo, fn ->
      [[count]] =
        Repo.query!(
          "SELECT count(*) FROM audit_events WHERE target_type = 'event' AND target_id = $1::uuid AND action = $2",
          [Ecto.UUID.dump!(event_id), action]
        ).rows

      count
    end)
  end

  defp assignment_count_unboxed(event_id, staff_id, role, status) do
    Sandbox.unboxed_run(Repo, fn -> assignment_count(event_id, staff_id, role, status) end)
  end

  defp start_event_lock_blocker(event_id) do
    parent = self()
    Task.async(fn -> hold_event_row_lock(parent, event_id) end)
  end

  defp hold_event_row_lock(parent, event_id) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.transaction(fn ->
        Repo.query!("SELECT id FROM events WHERE id = $1::uuid FOR UPDATE", [
          Ecto.UUID.dump!(event_id)
        ])

        send(parent, {:gls12_event_lock_held, database_backend_pid()})

        receive do
          :release_gls12_lock -> :released
        after
          15_000 -> Repo.rollback(:event_lock_blocker_timeout)
        end
      end)
    end)
  end

  defp start_staff_status_blocker(staff_id, status) do
    parent = self()
    Task.async(fn -> hold_staff_status_lock(parent, staff_id, status) end)
  end

  defp hold_staff_status_lock(parent, staff_id, status) do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.transaction(fn ->
        Repo.query!("SELECT id FROM staff_users WHERE id = $1::uuid FOR UPDATE", [
          Ecto.UUID.dump!(staff_id)
        ])

        Repo.query!("UPDATE staff_users SET status = $1 WHERE id = $2::uuid", [
          Atom.to_string(status),
          Ecto.UUID.dump!(staff_id)
        ])

        send(parent, {:gls12_staff_status_locked, database_backend_pid()})

        receive do
          :release_gls12_status -> :released
        after
          15_000 -> Repo.rollback(:staff_status_blocker_timeout)
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

  defp await_lock_waiters!(backend_pids) do
    deadline = System.monotonic_time(:millisecond) + 10_000
    do_await_lock_waiters(backend_pids, deadline)
  end

  defp do_await_lock_waiters(backend_pids, deadline) do
    waiters =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!(
          "SELECT pid FROM pg_stat_activity WHERE pid = ANY($1::int[]) AND wait_event_type = 'Lock'",
          [backend_pids]
        ).rows
        |> Enum.map(&hd/1)
      end)

    if length(Enum.uniq(waiters)) == length(backend_pids) do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk("expected each independent PostgreSQL session to wait on a row lock")
      else
        Process.sleep(10)
        do_await_lock_waiters(backend_pids, deadline)
      end
    end
  end

  defp database_backend_pid do
    Repo.query!("SELECT pg_backend_pid()").rows |> hd() |> hd()
  end

  defp release_event_blocker(blocker) do
    if Process.alive?(blocker.pid) do
      send(blocker.pid, :release_gls12_lock)
      Task.await(blocker, 10_000)
    end
  end

  defp release_status_blocker(blocker) do
    if Process.alive?(blocker.pid) do
      send(blocker.pid, :release_gls12_status)
      Task.await(blocker, 10_000)
    end
  end

  defp cleanup_committed_fixture(event_id, staff_ids) do
    Sandbox.unboxed_run(Repo, fn ->
      dumped_staff_ids = Enum.map(staff_ids, &Ecto.UUID.dump!/1)

      Repo.query!(
        "DELETE FROM audit_events WHERE target_id = $1::uuid OR actor_staff_user_id = ANY($2::uuid[]) OR target_id = ANY($2::uuid[])",
        [Ecto.UUID.dump!(event_id), dumped_staff_ids]
      )

      Repo.query!("DELETE FROM event_staff_assignments WHERE event_id = $1::uuid", [
        Ecto.UUID.dump!(event_id)
      ])

      Repo.query!("DELETE FROM events WHERE id = $1::uuid", [Ecto.UUID.dump!(event_id)])
      Repo.query!("DELETE FROM staff_users WHERE id = ANY($1::uuid[])", [dumped_staff_ids])
    end)
  end

  defp refute_exported?(module, function) do
    Code.ensure_loaded?(module) and
      not function_exported?(module, function, 1) and
      not function_exported?(module, function, 2)
  end
end
