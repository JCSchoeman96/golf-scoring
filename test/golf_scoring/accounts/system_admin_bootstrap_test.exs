defmodule GolfScoring.Accounts.SystemAdminBootstrapTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias Ash.Resource.Info
  alias AshAuthentication.Strategy.Password.Actions
  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Accounts.Services.BootstrapSystemAdmin
  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Accounts.SystemAdminGuard
  alias GolfScoring.Audit
  alias GolfScoring.Audit.AuditEvent
  alias GolfScoring.Release
  alias GolfScoring.Repo
  alias GolfScoringWeb.Router

  require Ash.Query

  @password "Synthetic bootstrap passphrase 2026"
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

  test "creates the first active authenticated SYSTEM_ADMIN and one safe system audit" do
    email = unique_email()

    assert {:ok, result} = BootstrapSystemAdmin.bootstrap(email, @password, release_context())
    assert result.mode == :created
    assert result.staff_user_id
    refute Map.has_key?(result, :hashed_password)

    assert user = user_by_email(email)
    assert user.id == result.staff_user_id
    assert to_string(user.email) == email
    assert user.status == :active
    assert user.system_admin
    assert %Ash.NotLoaded{field: :hashed_password} = user.hashed_password

    strategy = AshAuthentication.Info.strategy!(StaffUser, :password)

    assert {:ok, authenticated_user} =
             Actions.sign_in(
               strategy,
               %{"email" => email, "password" => @password},
               authorize?: false
             )

    assert authenticated_user.id == user.id
    assert [event] = bootstrap_audits(user.id)
    assert event.actor_staff_user_id == nil
    assert event.action == "system_admin_bootstrapped"
    assert event.target_type == "staff_user"
    assert event.target_id == Ecto.UUID.cast!(user.id)
    assert event.context == %{"source" => "release_bootstrap", "mode" => "created"}
    assert event.changes == %{"system_admin" => %{"from" => false, "to" => true}}
  end

  test "promotes an active non-admin without changing its password" do
    user = create_staff_user!()
    hash_before = stored_hash(user.id)

    assert {:ok, result} =
             BootstrapSystemAdmin.bootstrap(to_string(user.email), nil, release_context())

    assert result.mode == :promoted
    assert result.staff_user_id == user.id
    assert stored_hash(user.id) == hash_before
    assert Repo.get!(StaffUser, user.id).system_admin

    strategy = AshAuthentication.Info.strategy!(StaffUser, :password)

    assert {:ok, authenticated_user} =
             Actions.sign_in(
               strategy,
               %{"email" => to_string(user.email), "password" => @password},
               authorize?: false
             )

    assert authenticated_user.id == user.id
    assert [event] = bootstrap_audits(user.id)
    assert event.context == %{"source" => "release_bootstrap", "mode" => "promoted"}
  end

  test "refuses suspended and disabled targets without mutation or success audit" do
    for status <- [:suspended, :disabled] do
      user = create_staff_user!()
      set_status!(user.id, status)

      assert {:error, :inactive_target} =
               BootstrapSystemAdmin.bootstrap(to_string(user.email), nil, release_context())

      assert Repo.get!(StaffUser, user.id).status == status
      refute Repo.get!(StaffUser, user.id).system_admin
      assert bootstrap_audits(user.id) == []
    end
  end

  test "requires a password only when it must create the StaffUser" do
    email = unique_email()

    assert {:error, :password_required} =
             BootstrapSystemAdmin.bootstrap(email, nil, release_context())

    assert user_by_email(email) == nil
    assert bootstrap_audits() == []

    existing = create_staff_user!()

    assert {:ok, result} =
             BootstrapSystemAdmin.bootstrap(to_string(existing.email), nil, release_context())

    assert result.mode == :promoted
  end

  test "refuses bootstrap after an active SYSTEM_ADMIN exists without creating another user" do
    admin = create_system_admin!()
    email = unique_email()

    assert {:error, :active_system_admin_exists} =
             BootstrapSystemAdmin.bootstrap(email, @password, release_context())

    assert active_admin_count() == 1
    assert user_by_email(email) == nil
    assert bootstrap_audits() == []
    assert Repo.get!(StaffUser, admin.id).system_admin
  end

  test "rolls back the new StaffUser if the bootstrap audit write fails" do
    email = unique_email()
    existing_user = create_staff_user!()
    existing_hash = stored_hash(existing_user.id)

    Repo.query!("""
    CREATE FUNCTION gls8_reject_bootstrap_audit() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.action = 'system_admin_bootstrapped' THEN
        RAISE EXCEPTION 'simulated bootstrap audit failure';
      END IF;
      RETURN NEW;
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER gls8_reject_bootstrap_audit
    BEFORE INSERT ON audit_events
    FOR EACH ROW EXECUTE FUNCTION gls8_reject_bootstrap_audit()
    """)

    assert {:error, reason} =
             BootstrapSystemAdmin.bootstrap(email, @password, release_context())

    assert reason in [:audit_failed, :bootstrap_failed]

    assert {:error, reason} =
             BootstrapSystemAdmin.bootstrap(
               to_string(existing_user.email),
               nil,
               release_context()
             )

    assert reason in [:audit_failed, :bootstrap_failed]
    assert user_by_email(email) == nil
    refute Repo.get!(StaffUser, existing_user.id).system_admin
    assert stored_hash(existing_user.id) == existing_hash
    assert bootstrap_audits() == []
  end

  test "system-originated audit events reject credential keys" do
    assert {:error, _error} =
             Audit.record_system_event(
               %{
                 action: "system_admin_bootstrapped",
                 target_type: "staff_user",
                 target_id: Ecto.UUID.generate(),
                 context: %{"nested" => %{"PASSWORD_CONFIRMATION" => "must not persist"}},
                 changes: %{}
               },
               authorize?: false
             )

    assert bootstrap_audits() == []
  end

  test "system admin remains private and no bootstrap web endpoint is exposed" do
    system_admin = Info.attribute(StaffUser, :system_admin)
    bootstrap_action = Info.action(StaffUser, :bootstrap_system_admin)
    system_audit_action = Info.action(AuditEvent, :record_system_event)

    refute system_admin.public?
    refute system_admin.writable?
    refute bootstrap_action.public?
    assert bootstrap_action.accept == []
    refute system_audit_action.public?
    refute :actor_staff_user_id in system_audit_action.accept
    assert is_nil(Info.action(StaffUser, :update))
    refute function_exported?(Accounts, :bootstrap_system_admin, 1)

    refute Enum.any?(Router.__routes__(), fn route ->
             String.contains?(route.path, "bootstrap")
           end)
  end

  test "the private provisioning action rejects generic system_admin input" do
    email = unique_email()

    changeset =
      Ash.Changeset.for_create(
        StaffUser,
        :provision_staff_user,
        %{
          email: email,
          password: @password,
          password_confirmation: @password,
          system_admin: true
        }
      )

    assert {:error, _error} = Ash.create(changeset, authorize?: false)
    assert user_by_email(email) == nil
  end

  test "the release boundary requires email and gives safe operator errors" do
    with_bootstrap_env(nil, nil, fn ->
      output =
        capture_io(fn ->
          assert_raise RuntimeError, ~r/GOLF_SCORING_BOOTSTRAP_EMAIL is required/, fn ->
            Release.bootstrap_system_admin()
          end
        end)

      refute output =~ @password
    end)

    email = unique_email()

    with_bootstrap_env(email, nil, fn ->
      output =
        capture_io(fn ->
          assert_raise RuntimeError, ~r/password is required for a new StaffUser/, fn ->
            Release.bootstrap_system_admin()
          end
        end)

      refute output =~ @password
      assert System.get_env("GOLF_SCORING_BOOTSTRAP_PASSWORD") == nil
      assert user_by_email(email) == nil
    end)
  end

  test "release promotion needs no password and keeps operator output credential-free" do
    user = create_staff_user!()
    hash_before = stored_hash(user.id)

    {output, logs} =
      capture_release_call(fn ->
        with_bootstrap_env(to_string(user.email), nil, fn ->
          Release.bootstrap_system_admin()
        end)
      end)

    assert Repo.get!(StaffUser, user.id).system_admin
    assert stored_hash(user.id) == hash_before

    assert bootstrap_audits(user.id) |> Enum.map(& &1.context) ==
             [%{"source" => "release_bootstrap", "mode" => "promoted"}]

    refute output =~ @password
    refute output =~ hash_before
    refute logs =~ @password
    refute logs =~ hash_before
  end

  test "release reports a safe refusal when an active SYSTEM_ADMIN already exists" do
    _admin = create_system_admin!()
    email = unique_email()

    output =
      capture_io(fn ->
        with_bootstrap_env(email, @password, fn ->
          assert_raise RuntimeError, "an active SYSTEM_ADMIN already exists", fn ->
            Release.bootstrap_system_admin()
          end
        end)
      end)

    refute output =~ @password
    assert System.get_env("GOLF_SCORING_BOOTSTRAP_PASSWORD") == nil
    assert user_by_email(email) == nil
    assert bootstrap_audits() == []
  end

  test "release creation removes its password environment variable and does not print credentials" do
    email = unique_email()
    password = "Synthetic release bootstrap password 2026"

    {output, logs} =
      capture_release_call(fn ->
        with_bootstrap_env(email, password, fn ->
          assert :ok = Release.bootstrap_system_admin()
          assert System.get_env("GOLF_SCORING_BOOTSTRAP_PASSWORD") == nil
        end)
      end)

    assert user = user_by_email(email)
    assert user.system_admin
    refute output =~ password
    refute output =~ stored_hash(user.id)
    refute logs =~ password
    refute logs =~ stored_hash(user.id)
  end

  @tag :real_concurrency
  test "concurrent different-email bootstrap attempts use independent connections and leave no orphan" do
    emails = [unique_email(), unique_email()]
    blocker = start_lock_blocker()

    try do
      blocker_pid = await_lock_blocker!(blocker)

      tasks =
        Enum.map(emails, fn email ->
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              BootstrapSystemAdmin.bootstrap(email, @password, release_context())
            end)
          end)
        end)

      waiting_pids = await_two_lock_waiters!()
      assert length(Enum.uniq(waiting_pids)) == 2
      refute blocker_pid in waiting_pids

      send(blocker.pid, :release_system_admin_lock)
      assert {:ok, :released} = Task.await(blocker, 10_000)
      results = Enum.map(tasks, &Task.await(&1, 10_000))

      assert Enum.count(results, &match?({:ok, %{mode: :created}}, &1)) == 1
      assert Enum.count(results, &match?({:error, :active_system_admin_exists}, &1)) == 1
      assert active_admin_count() == 1
      assert Enum.count(Enum.map(emails, &user_by_email/1), &(!is_nil(&1))) == 1
      assert length(bootstrap_audits()) == 1
    after
      release_lock_blocker(blocker)
      cleanup_bootstrap_data(emails)
    end
  end

  @tag :real_concurrency
  test "concurrent same-email bootstrap attempts leave one user and one audit" do
    email = unique_email()
    blocker = start_lock_blocker()

    try do
      _blocker_pid = await_lock_blocker!(blocker)

      tasks =
        [
          "Synthetic same email password one 2026",
          "Synthetic same email password two 2026"
        ]
        |> Enum.map(fn password ->
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              BootstrapSystemAdmin.bootstrap(email, password, release_context())
            end)
          end)
        end)

      waiting_pids = await_two_lock_waiters!()
      assert length(Enum.uniq(waiting_pids)) == 2

      send(blocker.pid, :release_system_admin_lock)
      assert {:ok, :released} = Task.await(blocker, 10_000)
      results = Enum.map(tasks, &Task.await(&1, 10_000))

      assert Enum.count(results, &match?({:ok, %{mode: :created}}, &1)) == 1
      assert Enum.count(results, &match?({:error, :active_system_admin_exists}, &1)) == 1
      assert active_admin_count() == 1
      assert [user] = users_by_email(email)
      assert length(bootstrap_audits(user.id)) == 1
    after
      release_lock_blocker(blocker)
      cleanup_bootstrap_data([email])
    end
  end

  defp release_context, do: %{"source" => "release_bootstrap"}

  defp unique_email do
    "bootstrap-#{System.unique_integer([:positive])}@example.com"
  end

  defp create_staff_user! do
    attrs = %{
      email: unique_email(),
      password: @password,
      password_confirmation: @password
    }

    StaffUser
    |> Ash.Changeset.for_create(:provision_staff_user, attrs)
    |> Ash.create!(authorize?: false)
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

  defp set_status!(id, status) do
    assert %Postgrex.Result{num_rows: 1} =
             Repo.query!(
               "UPDATE staff_users SET status = $1 WHERE id = $2::uuid",
               [Atom.to_string(status), Ecto.UUID.dump!(id)]
             )
  end

  defp user_by_email(email) do
    StaffUser
    |> Ash.Query.filter(email: email)
    |> Ash.read_one!(authorize?: false)
  end

  defp users_by_email(email) do
    StaffUser
    |> Ash.Query.filter(email: email)
    |> Ash.read!(authorize?: false)
  end

  defp stored_hash(id) do
    Repo.query!(
      "SELECT hashed_password FROM staff_users WHERE id = $1::uuid",
      [Ecto.UUID.dump!(id)]
    ).rows
    |> hd()
    |> hd()
  end

  defp active_admin_count do
    Repo.query!(
      "SELECT count(*) FROM staff_users WHERE status = 'active' AND system_admin = TRUE"
    ).rows
    |> hd()
    |> hd()
  end

  defp bootstrap_audits(target_id \\ nil) do
    query =
      if target_id do
        Repo.query!(
          """
          SELECT id::text, actor_staff_user_id::text, action, target_type, target_id::text,
                 context, changes
          FROM audit_events
          WHERE action = 'system_admin_bootstrapped' AND target_id = $1::uuid
          ORDER BY occurred_at
          """,
          [Ecto.UUID.dump!(target_id)]
        )
      else
        Repo.query!("""
        SELECT id::text, actor_staff_user_id::text, action, target_type, target_id::text,
               context, changes
        FROM audit_events
        WHERE action = 'system_admin_bootstrapped'
        ORDER BY occurred_at
        """)
      end

    Enum.map(query.rows, fn [id, actor, action, target_type, target_id, context, changes] ->
      %{
        id: id,
        actor_staff_user_id: actor,
        action: action,
        target_type: target_type,
        target_id: target_id,
        context: context,
        changes: changes
      }
    end)
  end

  defp cleanup_bootstrap_data(emails) do
    Repo.query!(
      """
      DELETE FROM audit_events
      WHERE action = 'system_admin_bootstrapped'
        AND target_id IN (
          SELECT id
          FROM staff_users
          WHERE lower(email::text) = ANY($1::text[])
        )
      """,
      [Enum.map(emails, &String.downcase/1)]
    )

    Repo.query!(
      "DELETE FROM staff_users WHERE lower(email::text) = ANY($1::text[])",
      [Enum.map(emails, &String.downcase/1)]
    )
  end

  defp with_bootstrap_env(email, password, fun) do
    previous_email = System.get_env("GOLF_SCORING_BOOTSTRAP_EMAIL")
    previous_password = System.get_env("GOLF_SCORING_BOOTSTRAP_PASSWORD")

    put_or_delete_env("GOLF_SCORING_BOOTSTRAP_EMAIL", email)
    put_or_delete_env("GOLF_SCORING_BOOTSTRAP_PASSWORD", password)

    try do
      fun.()
    after
      put_or_delete_env("GOLF_SCORING_BOOTSTRAP_EMAIL", previous_email)
      put_or_delete_env("GOLF_SCORING_BOOTSTRAP_PASSWORD", previous_password)
    end
  end

  defp capture_release_call(fun) do
    parent = self()

    output =
      capture_io(fn ->
        logs = capture_log(fun)
        send(parent, {:release_logs, logs})
      end)

    assert_receive {:release_logs, logs}
    {output, logs}
  end

  defp put_or_delete_env(key, nil), do: System.delete_env(key)
  defp put_or_delete_env(key, value), do: System.put_env(key, value)

  defp start_lock_blocker do
    parent = self()

    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn -> hold_system_admin_lock(parent) end)
    end)
  end

  defp hold_system_admin_lock(parent) do
    Repo.transaction(fn ->
      :ok = SystemAdminGuard.acquire_lock!()
      backend_pid = Repo.query!("SELECT pg_backend_pid()").rows |> hd() |> hd()
      send(parent, {:bootstrap_lock_held, backend_pid})

      receive do
        :release_system_admin_lock -> :released
      after
        15_000 -> Repo.rollback(:bootstrap_lock_blocker_timeout)
      end
    end)
  end

  defp await_lock_blocker!(blocker) do
    assert_receive {:bootstrap_lock_held, backend_pid}, 5_000
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
          "expected two independent bootstrap sessions waiting for the shared SYSTEM_ADMIN lock"
        )
      else
        Process.sleep(10)
        do_await_two_lock_waiters(deadline)
      end
    end
  end

  defp release_lock_blocker(blocker) do
    if Process.alive?(blocker.pid) do
      send(blocker.pid, :release_system_admin_lock)
      Task.shutdown(blocker, 1_000)
    end
  end
end
