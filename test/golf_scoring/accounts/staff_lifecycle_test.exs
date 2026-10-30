defmodule GolfScoring.Accounts.StaffLifecycleTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ash.Resource.Info
  alias AshAuthentication.Strategy.Password.Actions
  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Accounts.Services.ProvisionStaffUser
  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Accounts.SystemAdminGuard
  alias GolfScoring.Repo

  @password "Synthetic staff provisioning passphrase 2026"
  @lock_namespace 4_674_371
  @lock_identity 1

  setup tags do
    Process.put(:gls9_email_prefix, "gls9-#{Ecto.UUID.generate()}")
    on_exit(fn -> Process.delete(:gls9_email_prefix) end)

    if tags[:real_concurrency] do
      :ok = Sandbox.mode(Repo, :auto)
      on_exit(fn -> Sandbox.mode(Repo, :manual) end)
    else
      owner = Sandbox.start_owner!(Repo, shared: true)
      on_exit(fn -> Sandbox.stop_owner(owner) end)
    end

    :ok
  end

  test "an active SYSTEM_ADMIN provisions authenticated ordinary staff with one safe audit" do
    actor = create_system_admin!()
    email = unique_email()
    prior_level = Logger.get_process_level(self())

    {result, output, logs} = capture_provision(actor, email)

    assert {:ok, user} = result
    assert user.status == :active
    refute user.system_admin
    assert %Ash.NotLoaded{field: :hashed_password} = user.hashed_password
    refute Map.has_key?(user, :password)
    assert Logger.get_process_level(self()) == prior_level

    assert {:ok, authenticated_user} = sign_in(email)
    assert authenticated_user.id == user.id

    assert [event] = audit_events(user.id)
    assert Enum.at(event, 0) == "staff_user_provisioned"
    assert Enum.at(event, 1) == actor.id
    assert Enum.at(event, 2) == "staff_user"
    assert Enum.at(event, 3) == user.id
    assert Enum.at(event, 4) == %{"status" => %{"from" => nil, "to" => "active"}}
    refute inspect(event) =~ @password

    assert stored_hash = stored_hash(user.id)
    refute output =~ @password
    refute output =~ stored_hash
    refute logs =~ @password
    refute logs =~ stored_hash
    refute inspect(user) =~ @password
    refute inspect(user) =~ stored_hash
  end

  test "provisioning rejects unauthorized and stale actors without creating users or audits" do
    admin = create_system_admin!()
    ordinary = create_staff_user!()
    suspended_admin = create_system_admin!() |> set_status!(:suspended)
    disabled_admin = create_system_admin!() |> set_status!(:disabled)
    stale_capability_admin = create_system_admin!()
    stale_suspended_admin = create_system_admin!()
    stale_disabled_admin = create_system_admin!()

    set_system_admin!(stale_capability_admin, false)
    set_status!(stale_suspended_admin, :suspended)
    set_status!(stale_disabled_admin, :disabled)

    actors = [
      ordinary,
      suspended_admin,
      disabled_admin,
      stale_capability_admin,
      stale_suspended_admin,
      stale_disabled_admin,
      nil
    ]

    emails = Enum.map(actors, fn _actor -> unique_email() end)

    for {actor, email} <- Enum.zip(actors, emails) do
      assert {:error, :forbidden} = ProvisionStaffUser.provision(actor, provision_attrs(email))
      assert staff_user_count(email) == 0
    end

    assert staff_audits(admin.id) == []
  end

  test "provisioning refuses case-equivalent email identities with one success audit" do
    actor = create_system_admin!()
    email = unique_email()

    assert {:ok, user} = ProvisionStaffUser.provision(actor, provision_attrs(email))

    assert {:error, :email_already_exists} =
             ProvisionStaffUser.provision(
               actor,
               provision_attrs(String.upcase(email))
             )

    assert staff_user_count(email) == 1
    assert length(audit_events(user.id)) == 1
    assert Enum.at(hd(audit_events(user.id)), 0) == "staff_user_provisioned"
    assert staff_audits(actor.id) == ["staff_user_provisioned"]
  end

  test "credential log suppression restores an existing process logging level" do
    actor = create_system_admin!()
    previous_level = Logger.get_process_level(self())
    :ok = Logger.put_process_level(self(), :warning)

    try do
      assert {:ok, _user} =
               ProvisionStaffUser.provision(actor, provision_attrs(unique_email()))

      assert Logger.get_process_level(self()) == :warning
    after
      case previous_level do
        nil -> Logger.delete_process_level(self())
        level -> Logger.put_process_level(self(), level)
      end
    end
  end

  test "invalid credentials and audit failures roll back provisioning" do
    actor = create_system_admin!()
    mismatched_email = unique_email()

    assert {:error, :invalid_credentials} =
             ProvisionStaffUser.provision(actor, %{
               email: mismatched_email,
               password: @password,
               password_confirmation: "A different valid passphrase 2026"
             })

    assert staff_user_count(mismatched_email) == 0
    short_password = String.duplicate("x", 14)
    short_email = unique_email()

    assert {:error, :invalid_credentials} =
             ProvisionStaffUser.provision(actor, %{
               email: short_email,
               password: short_password,
               password_confirmation: short_password
             })

    assert staff_user_count(short_email) == 0
    assert staff_audits(actor.id) == []

    email = unique_email()
    install_audit_failure_trigger!()

    assert {:error, :audit_failed} =
             ProvisionStaffUser.provision(actor, provision_attrs(email))

    assert staff_user_count(email) == 0

    assert Repo.query!(
             "SELECT count(*) FROM audit_events WHERE action = 'staff_user_provisioned'"
           ).rows ==
             [[0]]
  end

  test "ordinary provisioning stays behind the service and named private lifecycle actions" do
    lifecycle_actions = [
      :suspend_staff_user,
      :reactivate_staff_user,
      :disable_staff_user
    ]

    for name <- lifecycle_actions do
      action = Info.action(StaffUser, name)
      refute action.public?
      assert action.accept == []
      assert action.transaction?
      refute action.require_atomic?
      refute action.atomic_upgrade?
    end

    assert Enum.sort(
             for action <- Info.actions(StaffUser), action.type == :update, do: action.name
           ) ==
             [
               :bootstrap_system_admin,
               :disable_staff_user,
               :grant_system_admin,
               :reactivate_staff_user,
               :revoke_system_admin,
               :suspend_staff_user
             ]

    for forbidden_action <- [
          :update,
          :set_status,
          :restore_disabled,
          :reactivate_disabled,
          :enable_disabled,
          :undelete_staff
        ] do
      assert is_nil(Info.action(StaffUser, forbidden_action))
    end

    refute function_exported?(Accounts, :provision_staff_user, 1)
    refute function_exported?(Accounts, :provision_staff_user, 2)
  end

  test "active staff can be suspended once and suspended staff cannot authenticate" do
    actor = create_system_admin!()
    target = create_staff_user!()

    assert {:ok, suspended} = Accounts.suspend_staff_user(target, actor: actor)
    assert suspended.status == :suspended
    refute suspended.system_admin
    assert %Ash.NotLoaded{field: :hashed_password} = suspended.hashed_password
    assert {:error, _error} = sign_in(to_string(target.email))

    assert {:error, _error} = Accounts.suspend_staff_user(target, actor: actor)
    assert [event] = audit_events(target.id)
    assert Enum.at(event, 0) == "staff_user_suspended"
    assert Enum.at(event, 1) == actor.id
    assert Enum.at(event, 4) == %{"status" => %{"from" => "active", "to" => "suspended"}}
  end

  test "suspended staff can be reactivated and disabled staff cannot be restored" do
    actor = create_system_admin!()
    suspended_target = create_staff_user!() |> set_status!(:suspended)

    assert {:ok, reactivated} = Accounts.reactivate_staff_user(suspended_target, actor: actor)
    assert reactivated.status == :active
    assert %Ash.NotLoaded{field: :hashed_password} = reactivated.hashed_password
    assert {:ok, authenticated_user} = sign_in(to_string(suspended_target.email))
    assert authenticated_user.id == suspended_target.id

    assert {:error, _error} = Accounts.reactivate_staff_user(reactivated, actor: actor)

    disabled_target = create_staff_user!() |> set_status!(:disabled)

    assert {:error, _error} = Accounts.reactivate_staff_user(disabled_target, actor: actor)
    assert Repo.get!(StaffUser, disabled_target.id).status == :disabled
    assert audit_actions(suspended_target.id) == ["staff_user_reactivated"]
    assert audit_events(disabled_target.id) == []
  end

  test "active and suspended staff can be disabled, and disabled is terminal" do
    actor = create_system_admin!()
    active_target = create_staff_user!()
    suspended_target = create_staff_user!() |> set_status!(:suspended)

    assert {:ok, disabled_active} = Accounts.disable_staff_user(active_target, actor: actor)
    assert disabled_active.status == :disabled
    assert %Ash.NotLoaded{field: :hashed_password} = disabled_active.hashed_password
    assert {:error, _error} = sign_in(to_string(active_target.email))

    assert {:ok, disabled_suspended} =
             Accounts.disable_staff_user(suspended_target, actor: actor)

    assert disabled_suspended.status == :disabled
    assert %Ash.NotLoaded{field: :hashed_password} = disabled_suspended.hashed_password
    assert {:error, _error} = Accounts.disable_staff_user(disabled_active, actor: actor)
    assert {:error, _error} = Accounts.reactivate_staff_user(disabled_active, actor: actor)
    assert Repo.get!(StaffUser, active_target.id).status == :disabled

    for target <- [active_target, suspended_target] do
      assert [event] = audit_events(target.id)
      assert Enum.at(event, 0) == "staff_user_disabled"
      assert Enum.at(event, 1) == actor.id

      assert Enum.at(event, 4) == %{
               "status" => %{
                 "from" => if(target.id == active_target.id, do: "active", else: "suspended"),
                 "to" => "disabled"
               }
             }
    end
  end

  test "lifecycle policies reject non-admin, inactive, nil, and stale SYSTEM_ADMIN actors" do
    target = create_staff_user!()
    ordinary = create_staff_user!()
    suspended_admin = create_system_admin!()
    disabled_admin = create_system_admin!()
    stale_capability_admin = create_system_admin!()
    stale_suspended_admin = create_system_admin!()
    stale_disabled_admin = create_system_admin!()

    set_status!(suspended_admin, :suspended)
    set_status!(disabled_admin, :disabled)
    set_system_admin!(stale_capability_admin, false)
    set_status!(stale_suspended_admin, :suspended)
    set_status!(stale_disabled_admin, :disabled)

    for actor <- [
          ordinary,
          suspended_admin,
          disabled_admin,
          stale_capability_admin,
          stale_suspended_admin,
          stale_disabled_admin,
          nil
        ] do
      assert {:error, _error} = Accounts.suspend_staff_user(target, actor: actor)
    end

    assert Repo.get!(StaffUser, target.id).status == :active
    assert audit_events(target.id) == []
  end

  test "lifecycle guards re-read stale target status and reject stale no-op transitions" do
    actor = create_system_admin!()
    stale_active_target = create_staff_user!()

    set_status!(stale_active_target, :suspended)

    assert {:error, _error} =
             Accounts.suspend_staff_user(stale_active_target, actor: actor)

    assert Repo.get!(StaffUser, stale_active_target.id).status == :suspended
    assert audit_events(stale_active_target.id) == []

    stale_suspended_target = create_staff_user!() |> set_status!(:suspended)
    set_status!(stale_suspended_target, :disabled)

    assert {:error, _error} =
             Accounts.reactivate_staff_user(stale_suspended_target, actor: actor)

    assert Repo.get!(StaffUser, stale_suspended_target.id).status == :disabled
    assert audit_events(stale_suspended_target.id) == []
  end

  test "audit failure rolls back suspend, reactivate, and disable transitions" do
    actor = create_system_admin!()
    active_target = create_staff_user!()
    suspended_target = create_staff_user!() |> set_status!(:suspended)
    install_audit_failure_trigger!()

    assert {:error, _error} = Accounts.suspend_staff_user(active_target, actor: actor)
    assert {:error, _error} = Accounts.reactivate_staff_user(suspended_target, actor: actor)
    assert {:error, _error} = Accounts.disable_staff_user(active_target, actor: actor)

    assert Repo.get!(StaffUser, active_target.id).status == :active
    assert Repo.get!(StaffUser, suspended_target.id).status == :suspended
    assert audit_events(active_target.id) == []
    assert audit_events(suspended_target.id) == []
  end

  test "last-admin removals are blocked and successful status changes preserve SYSTEM_ADMIN" do
    last_admin = create_system_admin!()

    assert {:error, _error} = Accounts.suspend_staff_user(last_admin, actor: last_admin)
    assert {:error, _error} = Accounts.disable_staff_user(last_admin, actor: last_admin)
    assert Repo.get!(StaffUser, last_admin.id).status == :active
    assert active_admin_count() == 1
    assert audit_events(last_admin.id) == []

    self_suspending_admin = create_system_admin!()
    remaining_admin = create_system_admin!()

    assert {:ok, suspended_admin} =
             Accounts.suspend_staff_user(self_suspending_admin, actor: self_suspending_admin)

    assert suspended_admin.status == :suspended
    assert suspended_admin.system_admin
    assert Repo.get!(StaffUser, remaining_admin.id).status == :active

    self_disabling_admin = create_system_admin!()
    remaining_admin = create_system_admin!()

    assert {:ok, disabled_admin} =
             Accounts.disable_staff_user(self_disabling_admin, actor: self_disabling_admin)

    assert disabled_admin.status == :disabled
    assert disabled_admin.system_admin
    assert Repo.get!(StaffUser, remaining_admin.id).status == :active
  end

  test "another active SYSTEM_ADMIN can reactivate or disable a suspended SYSTEM_ADMIN" do
    actor = create_system_admin!()
    target = create_system_admin!() |> set_status!(:suspended)

    assert {:ok, reactivated} = Accounts.reactivate_staff_user(target, actor: actor)
    assert reactivated.status == :active
    assert reactivated.system_admin

    assert {:ok, suspended_again} = Accounts.suspend_staff_user(reactivated, actor: actor)
    assert suspended_again.status == :suspended
    assert suspended_again.system_admin

    assert {:ok, disabled} = Accounts.disable_staff_user(suspended_again, actor: actor)
    assert disabled.status == :disabled
    assert disabled.system_admin

    assert audit_actions(target.id) == [
             "staff_user_reactivated",
             "staff_user_suspended",
             "staff_user_disabled"
           ]
  end

  @tag :real_concurrency
  test "two concurrent lifecycle removals leave exactly one active SYSTEM_ADMIN" do
    Process.put(:gls9_fixture_ids, [])
    Process.put(:gls9_lifecycle_tasks, [])
    Process.put(:gls9_lock_blocker, nil)

    try do
      admin_a = create_system_admin!()
      admin_b = create_system_admin!()
      blocker = start_lock_blocker()
      Process.put(:gls9_lock_blocker, blocker)
      blocker_db_pid = await_lock_blocker!(blocker)

      tasks = [
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Accounts.suspend_staff_user(admin_a, actor: admin_a)
          end)
        end),
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Accounts.disable_staff_user(admin_b, actor: admin_b)
          end)
        end)
      ]

      Process.put(:gls9_lifecycle_tasks, tasks)
      waiting_pids = await_two_lock_waiters!()
      assert length(Enum.uniq(waiting_pids)) == 2
      refute blocker_db_pid in waiting_pids

      send(blocker.pid, :release_staff_lifecycle_lock)
      assert {:ok, :released} = Task.await(blocker, 10_000)

      results = Enum.map(tasks, &Task.await(&1, 10_000))
      successes = Enum.count(results, &match?({:ok, _user}, &1))

      assert successes == 1
      assert [failed_result] = Enum.reject(results, &match?({:ok, _user}, &1))
      assert {:error, error} = failed_result
      assert inspect(error) =~ "last active SYSTEM_ADMIN"
      assert active_admin_count_unboxed() == 1
      assert audit_count(Process.get(:gls9_fixture_ids)) == successes
    after
      stop_lock_blocker()
      Enum.each(Process.get(:gls9_lifecycle_tasks, []), &Task.shutdown(&1, 1_000))
      Process.delete(:gls9_lifecycle_tasks)
      cleanup_users(Process.get(:gls9_fixture_ids, []))
      Process.delete(:gls9_fixture_ids)
    end
  end

  @tag :real_concurrency
  test "GLS-7 capability revocation and GLS-9 suspension share the active-admin lock" do
    Process.put(:gls9_fixture_ids, [])
    Process.put(:gls9_lifecycle_tasks, [])
    Process.put(:gls9_lock_blocker, nil)

    try do
      admin_a = create_system_admin!()
      admin_b = create_system_admin!()
      blocker = start_lock_blocker()
      Process.put(:gls9_lock_blocker, blocker)
      blocker_db_pid = await_lock_blocker!(blocker)

      tasks = [
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Accounts.revoke_system_admin(admin_a, actor: admin_a)
          end)
        end),
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Accounts.suspend_staff_user(admin_b, actor: admin_b)
          end)
        end)
      ]

      Process.put(:gls9_lifecycle_tasks, tasks)
      waiting_pids = await_two_lock_waiters!()
      assert length(Enum.uniq(waiting_pids)) == 2
      refute blocker_db_pid in waiting_pids

      send(blocker.pid, :release_staff_lifecycle_lock)
      assert {:ok, :released} = Task.await(blocker, 10_000)

      results = Enum.map(tasks, &Task.await(&1, 10_000))

      assert Enum.count(results, &match?({:ok, _user}, &1)) == 1
      assert [failed_result] = Enum.reject(results, &match?({:ok, _user}, &1))
      assert {:error, error} = failed_result
      assert inspect(error) =~ "last active SYSTEM_ADMIN"
      assert active_admin_count_unboxed() == 1
    after
      stop_lock_blocker()
      Enum.each(Process.get(:gls9_lifecycle_tasks, []), &Task.shutdown(&1, 1_000))
      Process.delete(:gls9_lifecycle_tasks)
      cleanup_users(Process.get(:gls9_fixture_ids, []))
      Process.delete(:gls9_fixture_ids)
    end
  end

  @tag :real_concurrency
  test "concurrent case-equivalent provisioning creates one identity and audit" do
    Process.put(:gls9_fixture_ids, [])
    Process.put(:gls9_lifecycle_tasks, [])
    Process.put(:gls9_lock_blocker, nil)

    try do
      actor = create_system_admin!()
      email = unique_email()
      blocker = start_lock_blocker()
      Process.put(:gls9_lock_blocker, blocker)
      blocker_db_pid = await_lock_blocker!(blocker)

      tasks = [
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            ProvisionStaffUser.provision(actor, provision_attrs(email))
          end)
        end),
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            ProvisionStaffUser.provision(actor, provision_attrs(String.upcase(email)))
          end)
        end)
      ]

      Process.put(:gls9_lifecycle_tasks, tasks)
      waiting_pids = await_two_lock_waiters!()
      assert length(Enum.uniq(waiting_pids)) == 2
      refute blocker_db_pid in waiting_pids

      send(blocker.pid, :release_staff_lifecycle_lock)
      assert {:ok, :released} = Task.await(blocker, 10_000)

      results = Enum.map(tasks, &Task.await(&1, 10_000))

      assert Enum.count(results, &match?({:ok, _user}, &1)) == 1
      assert Enum.count(results, &match?({:error, :email_already_exists}, &1)) == 1

      provisioned_user =
        Enum.find_value(results, fn
          {:ok, user} -> user
          _ -> nil
        end)

      assert provisioned_user
      track_fixture(provisioned_user)
      assert staff_user_count(email) == 1
      assert audit_actions(provisioned_user.id) == ["staff_user_provisioned"]
    after
      stop_lock_blocker()
      Enum.each(Process.get(:gls9_lifecycle_tasks, []), &Task.shutdown(&1, 1_000))
      Process.delete(:gls9_lifecycle_tasks)
      cleanup_users(Process.get(:gls9_fixture_ids, []))
      Process.delete(:gls9_fixture_ids)
    end
  end

  defp capture_provision(actor, email) do
    {output, logs} =
      ExUnit.CaptureLog.with_log([], fn ->
        capture_io(fn ->
          result = ProvisionStaffUser.provision(actor, provision_attrs(email))
          send(self(), {:gls9_provision_result, result})
          IO.puts(inspect(result))
        end)
      end)

    result =
      receive do
        {:gls9_provision_result, result} -> result
      after
        0 -> flunk("provisioning result was not captured")
      end

    {result, output, logs}
  end

  defp provision_attrs(email) do
    %{email: email, password: @password, password_confirmation: @password}
  end

  defp sign_in(email) do
    strategy = AshAuthentication.Info.strategy!(StaffUser, :password)

    Actions.sign_in(
      strategy,
      %{"email" => email, "password" => @password},
      authorize?: false
    )
  end

  defp create_staff_user!(attrs \\ %{}) do
    email = Map.get(attrs, :email, unique_email())

    user =
      StaffUser
      |> Ash.Changeset.for_create(:provision_staff_user, provision_attrs(email))
      |> Ash.create!(authorize?: false)

    track_fixture(user)
  end

  defp create_system_admin! do
    user = create_staff_user!()
    set_system_admin!(user, true)
    Repo.get!(StaffUser, user.id)
  end

  defp set_system_admin!(user, system_admin) do
    assert %Postgrex.Result{num_rows: 1} =
             Repo.query!("UPDATE staff_users SET system_admin = $1 WHERE id = $2::uuid", [
               system_admin,
               Ecto.UUID.dump!(user.id)
             ])

    user
  end

  defp set_status!(user, status) do
    assert %Postgrex.Result{num_rows: 1} =
             Repo.query!("UPDATE staff_users SET status = $1 WHERE id = $2::uuid", [
               Atom.to_string(status),
               Ecto.UUID.dump!(user.id)
             ])

    Repo.get!(StaffUser, user.id)
  end

  defp staff_user_count(email) do
    Repo.query!("SELECT count(*) FROM staff_users WHERE email = $1", [email]).rows
    |> hd()
    |> hd()
  end

  defp stored_hash(id) do
    Repo.query!("SELECT hashed_password FROM staff_users WHERE id = $1::uuid", [
      Ecto.UUID.dump!(id)
    ]).rows
    |> hd()
    |> hd()
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
    |> Enum.map(fn [action, actor_id, target_type, target_id, changes] ->
      [action, Ecto.UUID.cast!(actor_id), target_type, Ecto.UUID.cast!(target_id), changes]
    end)
  end

  defp audit_actions(target_id), do: Enum.map(audit_events(target_id), &hd/1)

  defp staff_audits(actor_id) do
    Repo.query!(
      "SELECT action FROM audit_events WHERE actor_staff_user_id = $1::uuid ORDER BY occurred_at",
      [Ecto.UUID.dump!(actor_id)]
    ).rows
    |> Enum.map(&hd/1)
  end

  defp install_audit_failure_trigger! do
    Repo.query!("""
    CREATE FUNCTION gls9_reject_staff_audit() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.action IN (
        'staff_user_provisioned',
        'staff_user_suspended',
        'staff_user_reactivated',
        'staff_user_disabled'
      ) THEN
        RAISE EXCEPTION 'simulated GLS-9 audit failure';
      END IF;
      RETURN NEW;
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER gls9_reject_staff_audit
    BEFORE INSERT ON audit_events
    FOR EACH ROW EXECUTE FUNCTION gls9_reject_staff_audit()
    """)
  end

  defp track_fixture(user) do
    case Process.get(:gls9_fixture_ids) do
      nil ->
        user

      ids ->
        Process.put(:gls9_fixture_ids, [user.id | ids])
        user
    end
  end

  defp start_lock_blocker do
    parent = self()

    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn -> hold_shared_lock(parent) end)
    end)
  end

  defp hold_shared_lock(parent) do
    Repo.transaction(fn ->
      :ok = SystemAdminGuard.acquire_lock!()
      backend_pid = database_backend_pid()
      send(parent, {:gls9_lock_held, backend_pid})

      receive do
        :release_staff_lifecycle_lock -> :released
      after
        15_000 -> Repo.rollback(:lock_blocker_timeout)
      end
    end)
  end

  defp await_lock_blocker!(blocker) do
    assert_receive {:gls9_lock_held, backend_pid}, 5_000
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
        flunk("expected two independent PostgreSQL sessions waiting for the shared GLS-7 lock")
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
    Repo.query!(
      "SELECT count(*) FROM staff_users WHERE status = 'active' AND system_admin = TRUE"
    ).rows
    |> hd()
    |> hd()
  end

  defp active_admin_count_unboxed do
    Sandbox.unboxed_run(Repo, fn -> active_admin_count() end)
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
    prefix = Process.get(:gls9_email_prefix) <> "%"

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

      Repo.query!(
        """
        DELETE FROM audit_events
        WHERE target_id IN (
          SELECT id FROM staff_users WHERE email::text LIKE $1
        )
        OR actor_staff_user_id IN (
          SELECT id FROM staff_users WHERE email::text LIKE $1
        )
        """,
        [prefix]
      )

      Repo.query!("DELETE FROM staff_users WHERE email::text LIKE $1", [prefix])
    end)
  end

  defp unique_email do
    "#{Process.get(:gls9_email_prefix)}-#{System.unique_integer([:positive])}@example.com"
  end

  defp stop_lock_blocker do
    case Process.get(:gls9_lock_blocker) do
      nil ->
        :ok

      blocker ->
        send(blocker.pid, :release_staff_lifecycle_lock)
        Task.shutdown(blocker, 1_000)
        Process.delete(:gls9_lock_blocker)
        :ok
    end
  end
end
