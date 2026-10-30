defmodule GolfScoring.Competition.Services.CreateEventTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Accounts.EventStaffAssignment
  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Audit.AuditEvent
  alias GolfScoring.Competition.Event
  alias GolfScoring.Competition.Services.CreateEvent
  alias GolfScoring.Repo

  require Ash.Query

  @password "GLS-13 synthetic staff passphrase 2026"

  setup do
    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    :ok
  end

  test "active SYSTEM_ADMIN creates a draft Event with initial EVENT_ADMIN assignment and audit" do
    admin = create_system_admin!()

    assert {:ok, %{event: event}} = CreateEvent.create(admin, %{"source" => "test"})

    assert event = Repo.get!(Event, event.id)
    assert event.state == :draft

    assert [assignment] =
             EventStaffAssignment
             |> Ash.Query.filter(event_id == ^event.id and staff_user_id == ^admin.id)
             |> Ash.read!(authorize?: false)

    assert assignment.role == :event_admin
    assert assignment.status == :active

    assert [audit] =
             AuditEvent
             |> Ash.Query.filter(
               target_type == "event" and target_id == ^event.id and action == "event_created"
             )
             |> Ash.read!(authorize?: false)

    assert audit.actor_staff_user_id == admin.id
    assert audit.target_type == "event"
    assert audit.target_id == Ecto.UUID.cast!(event.id)
    assert audit.context["initial_event_admin_staff_user_id"] == admin.id
  end

  test "rejects Event creation when the actor struct is stale after SYSTEM_ADMIN revocation" do
    actor_admin = create_system_admin!()
    other_admin = create_system_admin!()
    stale_actor = actor_admin

    assert {:ok, revoked} = Accounts.revoke_system_admin(actor_admin, actor: other_admin)
    assert revoked.system_admin == false

    events_before = event_count()
    assignments_before = assignment_count()
    audits_before = audit_count("event_created")

    assert stale_actor.system_admin == true
    assert stale_actor.status == :active

    assert {:error, :forbidden} = CreateEvent.create(stale_actor, %{})

    assert event_count() == events_before
    assert assignment_count() == assignments_before
    assert audit_count("event_created") == audits_before
  end

  test "ordinary active staff cannot create an Event" do
    staff = create_staff_user!()
    events_before = event_count()
    assignments_before = assignment_count()
    audits_before = audit_count("event_created")

    assert {:error, :forbidden} = CreateEvent.create(staff, %{})

    assert event_count() == events_before
    assert assignment_count() == assignments_before
    assert audit_count("event_created") == audits_before
  end

  test "inactive SYSTEM_ADMIN cannot create an Event" do
    for status <- [:suspended, :disabled] do
      admin = create_system_admin!()
      set_staff_status!(admin, status)
      events_before = event_count()
      assignments_before = assignment_count()
      audits_before = audit_count("event_created")

      assert {:error, :forbidden} = CreateEvent.create(Repo.get!(StaffUser, admin.id), %{})

      assert event_count() == events_before
      assert assignment_count() == assignments_before
      assert audit_count("event_created") == audits_before
    end
  end

  test "SYSTEM_ADMIN without Event assignment cannot publish an arbitrary Event" do
    admin = create_system_admin!()
    event = create_event_direct!()

    assert {:error, _error} =
             event
             |> Ash.Changeset.for_update(:publish_event, %{}, actor: admin)
             |> Ash.update()
  end

  test "assign_event_staff_role still requires an active Event Admin for that Event" do
    system_admin = create_system_admin!()
    event = create_event_direct!()
    target = create_staff_user!()

    assert {:error, _error} =
             Accounts.assign_event_staff_role(
               %{event_id: event.id, staff_user_id: target.id, role: :scoring_support},
               actor: system_admin
             )

    event_admin = create_event_admin_for!(event)

    assert {:ok, _} =
             Accounts.assign_event_staff_role(
               %{event_id: event.id, staff_user_id: target.id, role: :scoring_support},
               actor: event_admin
             )
  end

  test "rolls back the Event when the initial assignment insert fails" do
    admin = create_system_admin!()
    events_before = event_count()
    assignments_before = assignment_count()
    audits_before = audit_count("event_created")

    install_assignment_failure_trigger!()

    on_exit(fn -> drop_assignment_failure_trigger!() end)

    assert {:error, _reason} = CreateEvent.create(admin, %{})

    assert event_count() == events_before
    assert assignment_count() == assignments_before
    assert audit_count("event_created") == audits_before
  end

  test "rolls back the Event and assignment when the audit insert fails" do
    admin = create_system_admin!()
    events_before = event_count()
    assignments_before = assignment_count()
    audits_before = audit_count("event_created")

    install_audit_failure_trigger!()

    on_exit(fn -> drop_audit_failure_trigger!() end)

    assert {:error, _reason} = CreateEvent.create(admin, %{})

    assert event_count() == events_before
    assert assignment_count() == assignments_before
    assert audit_count("event_created") == audits_before
  end

  @tag :real_concurrency
  test "blocks concurrent SYSTEM_ADMIN revocation until CreateEvent commits" do
    :ok = Sandbox.mode(Repo, :auto)
    Process.put(:gls13_concurrency_cleanup, {nil, nil, nil})

    try do
      creator = create_system_admin!()
      other = create_system_admin!()
      Process.put(:gls13_concurrency_cleanup, {nil, creator.id, other.id})
      parent = self()

      create_task =
        Task.async(fn ->
          Process.put(:gls13_create_event_pause_parent, parent)

          Sandbox.unboxed_run(Repo, fn ->
            CreateEvent.create(creator, %{"source" => "concurrency"})
          end)
        end)

      assert_receive {:gls13_create_event_paused, create_backend_pid}, 10_000

      revoke_task =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, {:gls13_revoke_backend, database_backend_pid()})
            Accounts.revoke_system_admin(creator, actor: other)
          end)
        end)

      assert_receive {:gls13_revoke_backend, revoke_backend_pid}, 10_000
      assert await_blocked_by!(revoke_backend_pid, create_backend_pid)

      send(create_task.pid, :gls13_create_event_continue)

      assert {:ok, %{event: event}} = Task.await(create_task, 15_000)
      Process.put(:gls13_concurrency_cleanup, {event.id, creator.id, other.id})
      assert {:ok, revoked} = Task.await(revoke_task, 15_000)
      assert revoked.system_admin == false
      refute Repo.get!(StaffUser, creator.id).system_admin
      assert event.state == :draft
    after
      {event_id, creator_id, other_id} =
        Process.get(:gls13_concurrency_cleanup, {nil, nil, nil})

      Process.delete(:gls13_concurrency_cleanup)
      cleanup_concurrency_fixtures!(event_id, creator_id, other_id)
      :ok = Sandbox.mode(Repo, :manual)
    end
  end

  defp create_staff_user! do
    email = "gls13-#{System.unique_integer([:positive])}@example.com"

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

  defp create_event_direct! do
    Event
    |> Ash.Changeset.for_create(:create_internal, %{})
    |> Ash.create!(authorize?: false)
  end

  defp create_event_admin_for!(event) do
    staff = create_staff_user!()

    Repo.query!(
      "INSERT INTO event_staff_assignments (event_id, staff_user_id, role, status) VALUES ($1::uuid, $2::uuid, 'event_admin', 'active')",
      [Ecto.UUID.dump!(event.id), Ecto.UUID.dump!(staff.id)]
    )

    staff
  end

  defp set_staff_status!(staff, status) do
    Repo.query!("UPDATE staff_users SET status = $1 WHERE id = $2::uuid", [
      Atom.to_string(status),
      Ecto.UUID.dump!(staff.id)
    ])
  end

  defp event_count do
    [[count]] = Repo.query!("SELECT count(*) FROM events").rows
    count
  end

  defp assignment_count do
    [[count]] = Repo.query!("SELECT count(*) FROM event_staff_assignments").rows
    count
  end

  defp audit_count(action) do
    [[count]] = Repo.query!("SELECT count(*) FROM audit_events WHERE action = $1", [action]).rows
    count
  end

  defp install_assignment_failure_trigger! do
    Repo.query!("""
    CREATE FUNCTION gls13_reject_event_staff_assignment() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'simulated GLS-13 assignment failure';
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER gls13_reject_event_staff_assignment
    BEFORE INSERT ON event_staff_assignments
    FOR EACH ROW EXECUTE FUNCTION gls13_reject_event_staff_assignment()
    """)
  end

  defp drop_assignment_failure_trigger! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS gls13_reject_event_staff_assignment ON event_staff_assignments"
    )

    Repo.query!("DROP FUNCTION IF EXISTS gls13_reject_event_staff_assignment()")
  end

  defp install_audit_failure_trigger! do
    Repo.query!("""
    CREATE FUNCTION gls13_reject_create_event_audit() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.action = 'event_created' THEN
        RAISE EXCEPTION 'simulated GLS-13 audit failure';
      END IF;
      RETURN NEW;
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER gls13_reject_create_event_audit
    BEFORE INSERT ON audit_events
    FOR EACH ROW EXECUTE FUNCTION gls13_reject_create_event_audit()
    """)
  end

  defp drop_audit_failure_trigger! do
    Repo.query!("DROP TRIGGER IF EXISTS gls13_reject_create_event_audit ON audit_events")
    Repo.query!("DROP FUNCTION IF EXISTS gls13_reject_create_event_audit()")
  end

  defp database_backend_pid do
    [[pid]] = Repo.query!("SELECT pg_backend_pid()").rows
    pid
  end

  defp await_blocked_by!(blocked_pid, blocker_pid) do
    deadline = System.monotonic_time(:millisecond) + 10_000
    do_await_blocked_by!(blocked_pid, blocker_pid, deadline)
  end

  defp do_await_blocked_by!(blocked_pid, blocker_pid, deadline) do
    blocking =
      Repo.query!("SELECT pg_blocking_pids($1)", [blocked_pid]).rows
      |> List.flatten()

    cond do
      blocker_pid in blocking ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk(
          "expected backend #{blocked_pid} to wait on #{blocker_pid}, blocking=#{inspect(blocking)}"
        )

      true ->
        Process.sleep(50)
        do_await_blocked_by!(blocked_pid, blocker_pid, deadline)
    end
  end

  defp cleanup_concurrency_fixtures!(event_id, creator_id, other_id) do
    Sandbox.unboxed_run(Repo, fn ->
      if event_id do
        Repo.query!(
          "DELETE FROM audit_events WHERE target_type = 'event' AND target_id = $1::uuid",
          [Ecto.UUID.dump!(event_id)]
        )

        Repo.query!(
          "DELETE FROM event_staff_assignments WHERE event_id = $1::uuid",
          [Ecto.UUID.dump!(event_id)]
        )

        Repo.query!("DELETE FROM events WHERE id = $1::uuid", [Ecto.UUID.dump!(event_id)])
      end

      for staff_id <- Enum.reject([creator_id, other_id], &is_nil/1) do
        Repo.query!("DELETE FROM audit_events WHERE actor_staff_user_id = $1::uuid", [
          Ecto.UUID.dump!(staff_id)
        ])

        Repo.query!(
          "DELETE FROM audit_events WHERE target_type = 'staff_user' AND target_id = $1::uuid",
          [Ecto.UUID.dump!(staff_id)]
        )

        Repo.query!("DELETE FROM staff_users WHERE id = $1::uuid", [Ecto.UUID.dump!(staff_id)])
      end
    end)
  end
end
