defmodule GolfScoring.Accounts.StaffUserTest do
  use GolfScoring.DataCase, async: false

  alias AshAuthentication.Strategy.Password.Actions
  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Repo

  @password "Staff passphrase 2026"

  test "StaffUser is registered in the Accounts domain" do
    assert {:module, _staff_user} = Code.ensure_loaded(StaffUser)
    assert StaffUser in Ash.Domain.Info.resources(GolfScoring.Accounts)
  end

  test "persists an active staff user with a false system admin default" do
    assert {:ok, user} = create_staff_user()

    assert user.status == :active
    assert user.system_admin == false
    assert Repo.get(StaffUser, user.id).id == user.id
  end

  test "requires an email login identity" do
    assert {:error, _error} = create_staff_user(%{email: nil})

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "INSERT INTO staff_users (status, hashed_password) VALUES ($1, $2)",
        ["active", "test-hash"]
      )
    end
  end

  test "rejects duplicate email login identities" do
    email = unique_email()
    assert {:ok, _user} = create_staff_user(%{email: email})

    assert {:error, _error} = create_staff_user(%{email: email})
  end

  test "rejects case-equivalent email login identities" do
    assert {:ok, _user} = create_staff_user(%{email: "CaseSensitive@example.com"})

    assert {:error, _error} = create_staff_user(%{email: "casesensitive@EXAMPLE.COM"})
  end

  test "PostgreSQL enforces case-insensitive email uniqueness" do
    assert %Postgrex.Result{num_rows: 1} =
             Repo.query!(
               "INSERT INTO staff_users (email, status, hashed_password) VALUES ($1, $2, $3)",
               ["database-case@example.com", "active", "test-hash"]
             )

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "INSERT INTO staff_users (email, status, hashed_password) VALUES ($1, $2, $3)",
        ["DATABASE-CASE@EXAMPLE.COM", "active", "test-hash"]
      )
    end
  end

  test "PostgreSQL enforces the system admin default and non-null constraint" do
    assert %Postgrex.Result{rows: [[false]]} =
             Repo.query!(
               "INSERT INTO staff_users (email, status, hashed_password) VALUES ($1, $2, $3) RETURNING system_admin",
               [unique_email(), "active", "test-hash"]
             )

    assert %Postgrex.Result{rows: [["NO", column_default]]} =
             Repo.query!("""
             SELECT is_nullable, column_default
             FROM information_schema.columns
             WHERE table_schema = 'public'
               AND table_name = 'staff_users'
               AND column_name = 'system_admin'
             """)

    assert column_default =~ "false"

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        """
        INSERT INTO staff_users (email, status, system_admin, hashed_password)
        VALUES ($1, $2, NULL, $3)
        """,
        [unique_email(), "active", "test-hash"]
      )
    end
  end

  test "PostgreSQL requires an authentication credential hash" do
    assert_raise Postgrex.Error, fn ->
      Repo.query!("INSERT INTO staff_users (email, status) VALUES ($1, $2)", [
        unique_email(),
        "active"
      ])
    end
  end

  test "persists only the specified lifecycle values" do
    for status <- [:active, :suspended, :disabled] do
      assert {:ok, user} = create_staff_user(%{status: status})
      assert user.status == status
    end
  end

  test "rejects invalid lifecycle values in Ash and PostgreSQL" do
    assert {:error, _error} = create_staff_user(%{status: :pending})

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "INSERT INTO staff_users (email, status, hashed_password) VALUES ($1, $2, $3)",
        [unique_email(), "pending", "test-hash"]
      )
    end
  end

  test "stores an AshAuthentication hash and omits credentials from ordinary resource results" do
    assert {:ok, user} = create_staff_user()
    assert %Ash.NotLoaded{field: :hashed_password} = user.hashed_password
    refute Map.has_key?(user, :password)

    assert %Postgrex.Result{rows: [[stored_hash]]} =
             Repo.query!(
               "SELECT hashed_password FROM staff_users WHERE email::text = $1",
               [to_string(user.email)]
             )

    assert is_binary(stored_hash)
    assert stored_hash != @password
    assert String.starts_with?(stored_hash, "$2")

    assert {:ok, [read_user]} = Ash.read(StaffUser, authorize?: false)
    assert %Ash.NotLoaded{field: :hashed_password} = read_user.hashed_password
    refute inspect(user) =~ stored_hash
    refute inspect(user) =~ @password
  end

  test "requires matching password confirmation" do
    assert {:error, _error} =
             create_staff_user(%{password_confirmation: "A different passphrase"})
  end

  test "allows password authentication only for active staff" do
    strategy = AshAuthentication.Info.strategy!(StaffUser, :password)
    active_email = unique_email()
    assert {:ok, _active_user} = create_staff_user(%{email: active_email, status: :active})

    assert {:ok, _user} =
             Actions.sign_in(
               strategy,
               %{"email" => active_email, "password" => @password},
               authorize?: false
             )

    for status <- [:suspended, :disabled] do
      email = unique_email()
      assert {:ok, _user} = create_staff_user(%{email: email, status: status})

      assert {:error, _error} =
               Actions.sign_in(
                 strategy,
                 %{"email" => email, "password" => @password},
                 authorize?: false
               )
    end
  end

  test "normalizes email identity comparisons through citext" do
    strategy = AshAuthentication.Info.strategy!(StaffUser, :password)
    assert {:ok, _user} = create_staff_user(%{email: "Staff.Login@example.com"})

    assert {:ok, _user} =
             Actions.sign_in(
               strategy,
               %{"email" => "staff.login@EXAMPLE.COM", "password" => @password},
               authorize?: false
             )
  end

  test "does not expose registration or unrestricted protected-field updates" do
    strategy = AshAuthentication.Info.strategy!(StaffUser, :password)
    provision_action = Ash.Resource.Info.action(StaffUser, :provision_staff_user)
    hashed_password = Ash.Resource.Info.attribute(StaffUser, :hashed_password)
    system_admin = Ash.Resource.Info.attribute(StaffUser, :system_admin)

    refute strategy.registration_enabled?
    assert is_nil(Ash.Resource.Info.action(StaffUser, :register_with_password))
    refute provision_action.public?
    assert is_nil(Ash.Resource.Info.action(StaffUser, :update))
    assert is_nil(Ash.Resource.Info.action(StaffUser, :destroy))
    assert hashed_password.sensitive?
    refute hashed_password.public?
    refute hashed_password.select_by_default?
    refute system_admin.writable?
  end

  defp create_staff_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          email: unique_email(),
          status: :active,
          password: @password,
          password_confirmation: @password
        },
        overrides
      )

    StaffUser
    |> Ash.Changeset.for_create(:provision_staff_user, attrs)
    |> Ash.create(authorize?: false)
  end

  defp unique_email do
    "staff-#{System.unique_integer([:positive])}@example.com"
  end
end
