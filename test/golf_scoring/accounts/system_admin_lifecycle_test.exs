defmodule GolfScoring.Accounts.SystemAdminLifecycleTest do
  use ExUnit.Case, async: false

  alias Ash.Resource.Info
  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Accounts.SystemAdminGuard
  alias GolfScoring.Repo

  @password "Synthetic admin lifecycle passphrase 2026"
  @lock_namespace 4_674_371
  @lock_identity 1

  setup tags do
    if tags[:real_concurrency] do
      :ok = Sandbox.mode(Repo, :auto)
      on_exit(fn -> Sandbox.mode(Repo, :manual) end)
    else
      owner = Sandbox.start_owner!(Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(owner) end)
    end

    :ok
  end

  @tag :lock_transaction_guard
  test "the shared lock requires an explicit repository transaction" do
    assert_raise ArgumentError, ~r/SYSTEM_ADMIN.*transaction/i, fn ->
      SystemAdminGuard.acquire_lock!()
    end
  end

  @tag :lock_transaction_guard
  test "the shared lock is acquired inside an explicit repository transaction" do
    assert {:ok, :ok} =
             Repo.transaction(fn ->
               :ok = SystemAdminGuard.acquire_lock!()
             end)
  end

  @tag :credential_safe_action_results
  test "active system admin grants an active staff user with one safe audit event" do
    actor = create_system_admin!()
    target = create_staff_user!()

    assert {:ok, updated_target} = Accounts.grant_system_admin(target, actor: actor)

    assert updated_target.system_admin
    assert %Ash.NotLoaded{field: :hashed_password} = updated_target.hashed_password

    assert %Postgrex.Result{
             rows: [["system_admin_granted", actor_id, "staff_user", target_id, changes, context]],
             num_rows: 1
           } =
             Repo.query!(
               """
               SELECT action, actor_staff_user_id::text, target_type, target_id::text,
                      changes, context
               FROM audit_events
               WHERE target_id = $1::uuid
               """,
               [Ecto.UUID.dump!(target.id)]
             )

    assert actor_id == actor.id
    assert target_id == target.id
    assert changes == %{"system_admin" => %{"from" => false, "to" => true}}
    assert context == %{}
  end

  @tag :policy_authorization
  test "ordinary active staff cannot grant SYSTEM_ADMIN" do
    actor = create_staff_user!()
    target = create_staff_user!()

    assert {:error, %Ash.Error.Forbidden{}} = Accounts.grant_system_admin(target, actor: actor)
    refute Repo.get!(StaffUser, target.id).system_admin
    assert audit_events(target.id) == []
  end

  @tag :stale_actor_capability_recheck
  test "a stale SYSTEM_ADMIN actor cannot grant after losing the database capability" do
    stale_actor = create_system_admin!()
    target = create_staff_user!()

    assert stale_actor.system_admin

    assert %Postgrex.Result{num_rows: 1} =
             Repo.query!(
               "UPDATE staff_users SET system_admin = FALSE WHERE id = $1::uuid",
               [Ecto.UUID.dump!(stale_actor.id)]
             )

    assert stale_actor.system_admin
    assert {:error, _error} = Accounts.grant_system_admin(target, actor: stale_actor)
    refute Repo.get!(StaffUser, target.id).system_admin
    assert audit_events(target.id) == []
  end

  test "suspended and disabled SYSTEM_ADMIN actors cannot grant capability" do
    target = create_staff_user!()

    for status <- [:suspended, :disabled] do
      actor = create_system_admin!()
      set_status!(actor, status)

      assert {:error, _error} = Accounts.grant_system_admin(target, actor: actor)
      refute Repo.get!(StaffUser, target.id).system_admin
      assert audit_events(target.id) == []
    end
  end

  test "a nil actor cannot grant SYSTEM_ADMIN" do
    target = create_staff_user!()

    assert {:error, _error} = Accounts.grant_system_admin(target, actor: nil)
    refute Repo.get!(StaffUser, target.id).system_admin
    assert audit_events(target.id) == []
  end

  test "suspended and disabled StaffUsers cannot receive SYSTEM_ADMIN" do
    actor = create_system_admin!()

    for status <- [:suspended, :disabled] do
      target = create_staff_user!()
      set_status!(target, status)

      assert {:error, _error} = Accounts.grant_system_admin(target, actor: actor)
      refute Repo.get!(StaffUser, target.id).system_admin
      assert audit_events(target.id) == []
    end
  end

  test "a deleted target cannot receive SYSTEM_ADMIN" do
    actor = create_system_admin!()
    target = create_staff_user!()

    Repo.query!("DELETE FROM staff_users WHERE id = $1::uuid", [Ecto.UUID.dump!(target.id)])

    assert {:error, _error} = Accounts.grant_system_admin(target, actor: actor)
    assert audit_events(target.id) == []
  end

  test "an existing SYSTEM_ADMIN cannot be granted the capability again" do
    actor = create_system_admin!()
    target = create_system_admin!()

    assert {:error, _error} = Accounts.grant_system_admin(target, actor: actor)
    assert Repo.get!(StaffUser, target.id).system_admin
    assert audit_events(target.id) == []
  end

  @tag :credential_safe_action_results
  test "an active SYSTEM_ADMIN can revoke another while one remains" do
    actor = create_system_admin!()
    target = create_system_admin!()

    assert {:ok, updated_target} = Accounts.revoke_system_admin(target, actor: actor)

    refute updated_target.system_admin
    assert %Ash.NotLoaded{field: :hashed_password} = updated_target.hashed_password
    assert Repo.get!(StaffUser, actor.id).system_admin
    assert [event] = audit_events(target.id)
    assert Enum.at(event, 0) == "system_admin_revoked"
    assert Enum.at(event, 1) == actor.id
    assert Enum.at(event, 2) == "staff_user"
    assert Enum.at(event, 3) == target.id
    assert Enum.at(event, 4) == %{"system_admin" => %{"from" => true, "to" => false}}
  end

  test "revoke persists the locked capability when the target struct is stale" do
    actor = create_system_admin!()
    target = create_staff_user!()

    Repo.query!(
      "UPDATE staff_users SET system_admin = TRUE WHERE id = $1::uuid",
      [Ecto.UUID.dump!(target.id)]
    )

    assert {:ok, updated_target} = Accounts.revoke_system_admin(target, actor: actor)

    refute updated_target.system_admin
    refute Repo.get!(StaffUser, target.id).system_admin
    assert [event] = audit_events(target.id)
    assert Enum.at(event, 0) == "system_admin_revoked"
  end

  test "an active SYSTEM_ADMIN can revoke their own capability if another remains" do
    actor = create_system_admin!()
    other_admin = create_system_admin!()

    assert {:ok, updated_actor} = Accounts.revoke_system_admin(actor, actor: actor)

    refute updated_actor.system_admin
    assert Repo.get!(StaffUser, other_admin.id).system_admin
    assert length(audit_events(actor.id)) == 1
  end

  @tag :last_admin_guard
  test "the last active SYSTEM_ADMIN cannot revoke themselves" do
    actor = create_system_admin!()

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM staff_users WHERE status = 'active' AND system_admin = TRUE"
             ).rows

    assert {:error, _error} = Accounts.revoke_system_admin(actor, actor: actor)
    assert Repo.get!(StaffUser, actor.id).system_admin
    assert audit_events(actor.id) == []
  end

  test "a non-admin target cannot be revoked and creates no audit event" do
    actor = create_system_admin!()
    target = create_staff_user!()

    assert {:error, _error} = Accounts.revoke_system_admin(target, actor: actor)
    refute Repo.get!(StaffUser, target.id).system_admin
    assert audit_events(target.id) == []
  end

  test "a non-admin actor cannot revoke another SYSTEM_ADMIN" do
    actor = create_staff_user!()
    target = create_system_admin!()

    assert {:error, _error} = Accounts.revoke_system_admin(target, actor: actor)
    assert Repo.get!(StaffUser, target.id).system_admin
    assert audit_events(target.id) == []
  end

  test "a suspended or disabled StaffUser can have a stale SYSTEM_ADMIN capability revoked" do
    actor = create_system_admin!()

    for status <- [:suspended, :disabled] do
      target = create_system_admin!()
      set_status!(target, status)

      assert {:ok, updated_target} = Accounts.revoke_system_admin(target, actor: actor)
      refute updated_target.system_admin
      assert [event] = audit_events(target.id)
      assert Enum.at(event, 0) == "system_admin_revoked"
    end
  end

  test "SYSTEM_ADMIN remains non-writable through ordinary inputs" do
    attribute = Info.attribute(StaffUser, :system_admin)
    refute attribute.public?
    refute attribute.writable?
    assert is_nil(Info.action(StaffUser, :update))
  end

  test "grant and revoke actions are named and private" do
    grant = Info.action(StaffUser, :grant_system_admin)
    revoke = Info.action(StaffUser, :revoke_system_admin)
    bootstrap = Info.action(StaffUser, :bootstrap_system_admin)

    refute grant.public?
    refute revoke.public?
    refute bootstrap.public?
    assert grant.accept == []
    assert revoke.accept == []
    assert bootstrap.accept == []

    assert Enum.sort(
             for action <- Info.actions(StaffUser),
                 action.type == :update,
                 do: action.name
           ) ==
             [
               :bootstrap_system_admin,
               :disable_staff_user,
               :grant_system_admin,
               :reactivate_staff_user,
               :revoke_system_admin,
               :suspend_staff_user
             ]
  end

  test "audit failure rolls back the SYSTEM_ADMIN capability change" do
    actor = create_system_admin!()
    target = create_staff_user!()

    Repo.query!("""
    CREATE FUNCTION gls7_reject_system_admin_audit() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.action = 'system_admin_granted' THEN
        RAISE EXCEPTION 'simulated SYSTEM_ADMIN audit failure';
      END IF;
      RETURN NEW;
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER gls7_reject_system_admin_audit
    BEFORE INSERT ON audit_events
    FOR EACH ROW EXECUTE FUNCTION gls7_reject_system_admin_audit()
    """)

    assert {:error, _error} = Accounts.grant_system_admin(target, actor: actor)
    refute Repo.get!(StaffUser, target.id).system_admin
    assert audit_events(target.id) == []
  end

  defp create_system_admin! do
    user = create_staff_user!()

    assert %Postgrex.Result{num_rows: 1} =
             Repo.query!(
               "UPDATE staff_users SET system_admin = TRUE WHERE id = $1::uuid",
               [Ecto.UUID.dump!(user.id)]
             )

    Repo.get!(StaffUser, user.id)
  end

  defp create_staff_user! do
    attrs = %{
      email: "staff-#{System.unique_integer([:positive])}@example.com",
      password: @password,
      password_confirmation: @password
    }

    StaffUser
    |> Ash.Changeset.for_create(:provision_staff_user, attrs)
    |> Ash.create!(authorize?: false)
    |> track_fixture()
  end

  defp track_fixture(user) do
    case Process.get(:gls7_fixture_ids) do
      nil ->
        user

      ids ->
        Process.put(:gls7_fixture_ids, [user.id | ids])
        user
    end
  end

  defp set_status!(user, status) do
    assert %Postgrex.Result{num_rows: 1} =
             Repo.query!(
               "UPDATE staff_users SET status = $1 WHERE id = $2::uuid",
               [Atom.to_string(status), Ecto.UUID.dump!(user.id)]
             )
  end

  defp audit_events(target_id) do
    Repo.query!(
      """
      SELECT action, actor_staff_user_id::text, target_type, target_id::text, changes
      FROM audit_events
      WHERE target_id = $1::uuid
      ORDER BY occurred_at
      """,
      [Ecto.UUID.dump!(target_id)]
    ).rows
  end

  @tag :real_concurrency
  test "concurrent self-revocations leave one active SYSTEM_ADMIN" do
    Process.put(:gls7_fixture_ids, [])
    Process.put(:gls7_system_admin_tasks, [])
    Process.put(:gls7_lock_blocker, nil)

    try do
      admin_a = create_system_admin!()
      admin_b = create_system_admin!()
      blocker = start_lock_blocker()
      Process.put(:gls7_lock_blocker, blocker)
      blocker_db_pid = await_lock_blocker!(blocker)

      tasks = [
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Accounts.revoke_system_admin(admin_a, actor: admin_a)
          end)
        end),
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Accounts.revoke_system_admin(admin_b, actor: admin_b)
          end)
        end)
      ]

      Process.put(:gls7_system_admin_tasks, tasks)

      waiting_pids = await_two_lock_waiters!()
      assert length(Enum.uniq(waiting_pids)) == 2
      refute blocker_db_pid in waiting_pids

      send(blocker.pid, :release_system_admin_lock)
      assert {:ok, :released} = Task.await(blocker, 10_000)

      results = Enum.map(tasks, &Task.await(&1, 10_000))
      successful_transitions = Enum.count(results, &match?({:ok, _user}, &1))

      assert successful_transitions == 1
      assert active_admin_count() == 1
      assert audit_count(Process.get(:gls7_fixture_ids)) == successful_transitions
    after
      stop_lock_blocker()
      Enum.each(Process.get(:gls7_system_admin_tasks, []), &Task.shutdown(&1, 1_000))
      Process.delete(:gls7_system_admin_tasks)
      cleanup_users(Process.get(:gls7_fixture_ids, []))
      Process.delete(:gls7_fixture_ids)
    end
  end

  @tag :real_concurrency
  test "concurrent grant and last-admin revoke preserve one active SYSTEM_ADMIN" do
    Process.put(:gls7_fixture_ids, [])
    Process.put(:gls7_system_admin_tasks, [])
    Process.put(:gls7_lock_blocker, nil)

    try do
      admin = create_system_admin!()
      target = create_staff_user!()
      blocker = start_lock_blocker()
      Process.put(:gls7_lock_blocker, blocker)
      blocker_db_pid = await_lock_blocker!(blocker)

      grant_task =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Accounts.grant_system_admin(target, actor: admin)
          end)
        end)

      revoke_task =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Accounts.revoke_system_admin(admin, actor: admin)
          end)
        end)

      tasks = [grant_task, revoke_task]
      Process.put(:gls7_system_admin_tasks, tasks)
      waiting_pids = await_two_lock_waiters!()
      assert length(Enum.uniq(waiting_pids)) == 2
      refute blocker_db_pid in waiting_pids

      send(blocker.pid, :release_system_admin_lock)
      assert {:ok, :released} = Task.await(blocker, 10_000)

      grant_result = Task.await(grant_task, 10_000)
      revoke_result = Task.await(revoke_task, 10_000)

      assert {:ok, granted_target} = grant_result
      assert granted_target.system_admin
      assert active_admin_count() >= 1

      assert audit_count(Process.get(:gls7_fixture_ids)) ==
               Enum.count([grant_result, revoke_result], &match?({:ok, _}, &1))
    after
      stop_lock_blocker()
      Enum.each(Process.get(:gls7_system_admin_tasks, []), &Task.shutdown(&1, 1_000))
      Process.delete(:gls7_system_admin_tasks)
      cleanup_users(Process.get(:gls7_fixture_ids, []))
      Process.delete(:gls7_fixture_ids)
    end
  end

  defp stop_lock_blocker do
    case Process.get(:gls7_lock_blocker) do
      nil ->
        :ok

      blocker ->
        send(blocker.pid, :release_system_admin_lock)
        Task.shutdown(blocker, 1_000)
        Process.delete(:gls7_lock_blocker)
        :ok
    end
  end

  defp start_lock_blocker do
    parent = self()

    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        block_while_lock_held(parent)
      end)
    end)
  end

  defp block_while_lock_held(parent) do
    Repo.transaction(fn ->
      :ok = SystemAdminGuard.acquire_lock!()
      backend_pid = database_backend_pid()
      send(parent, {:system_admin_lock_held, backend_pid})

      receive do
        :release_system_admin_lock -> :released
      after
        15_000 -> Repo.rollback(:lock_blocker_timeout)
      end
    end)
  end

  defp await_lock_blocker!(blocker) do
    assert_receive {:system_admin_lock_held, backend_pid}, 5_000
    assert blocker.pid != self()
    backend_pid
  end

  defp await_two_lock_waiters! do
    deadline = System.monotonic_time(:millisecond) + 10_000
    do_await_two_lock_waiters(deadline)
  end

  defp do_await_two_lock_waiters(deadline) do
    pids =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!(
          """
          SELECT pid
          FROM pg_locks
          WHERE locktype = 'advisory'
            AND classid = $1::oid
            AND objid = $2::oid
            AND objsubid = 2
            AND NOT granted
          """,
          [@lock_namespace, @lock_identity]
        ).rows
        |> Enum.map(&hd/1)
      end)

    if length(pids) == 2 do
      pids
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk(
          "expected two independent PostgreSQL sessions waiting for the SYSTEM_ADMIN lock, got #{inspect(pids)}"
        )
      else
        Process.sleep(10)
        do_await_two_lock_waiters(deadline)
      end
    end
  end

  defp database_backend_pid do
    Repo.query!("SELECT pg_backend_pid()").rows |> hd() |> hd()
  end

  defp active_admin_count do
    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!(
        "SELECT count(*) FROM staff_users WHERE status = 'active' AND system_admin = TRUE"
      ).rows
      |> hd()
      |> hd()
    end)
  end

  defp audit_count(user_ids) do
    Enum.reduce(user_ids, 0, fn id, count ->
      count +
        Sandbox.unboxed_run(Repo, fn ->
          Repo.query!("SELECT count(*) FROM audit_events WHERE target_id = $1::uuid", [
            Ecto.UUID.dump!(id)
          ]).rows
          |> hd()
          |> hd()
        end)
    end)
  end

  defp cleanup_users(user_ids) do
    Sandbox.unboxed_run(Repo, fn ->
      Enum.each(user_ids, fn id ->
        uuid = Ecto.UUID.dump!(id)

        Repo.query!(
          "DELETE FROM audit_events WHERE actor_staff_user_id = $1::uuid OR target_id = $1::uuid",
          [uuid]
        )
      end)

      Enum.each(user_ids, fn id ->
        Repo.query!("DELETE FROM staff_users WHERE id = $1::uuid", [Ecto.UUID.dump!(id)])
      end)
    end)
  end
end
