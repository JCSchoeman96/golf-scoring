defmodule GolfScoringWeb.Admin.SessionControllerTest do
  use GolfScoringWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Repo
  alias GolfScoringWeb.Router

  @password "Synthetic staff passphrase 2026"
  @sign_in_form "#staffuser-password-sign-in-with-password"

  setup tags do
    owner = Sandbox.start_owner!(Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  test "unauthenticated requests to the staff foundation redirect to sign in", %{conn: conn} do
    conn = get(conn, "/admin")

    assert redirected_to(conn) == "/admin/sign-in"
  end

  test "the sign-in page renders password authentication only", %{conn: conn} do
    conn = get(conn, "/admin/sign-in")
    body = html_response(conn, 200)

    assert body =~ "Email"
    assert body =~ "Password"
    refute body =~ "Register"
    refute body =~ "Magic link"
    refute body =~ "Google"
    refute body =~ "Reset password"
  end

  test "staff authentication exposes no registration, magic-link, OAuth, or reset flow" do
    assert [strategy] = AshAuthentication.Info.authentication_strategies(StaffUser)
    assert strategy.__struct__ == AshAuthentication.Strategy.Password
    refute strategy.registration_enabled?
    refute AshAuthentication.Info.authentication_tokens_enabled?(StaffUser)

    for action <- [
          :register_with_password,
          :request_password_reset,
          :reset_password_with_token,
          :sign_in_with_magic_link
        ] do
      assert is_nil(Ash.Resource.Info.action(StaffUser, action))
    end

    refute Enum.any?(Router.__routes__(), fn route ->
             String.contains?(route.path, ["register", "magic", "oauth", "reset"])
           end)
  end

  test "active staff can authenticate and reach the staff foundation", %{conn: conn} do
    user = create_staff_user!()
    conn = authenticate(conn, user.email)

    conn = conn |> recycle() |> get("/admin")

    assert conn.status == 204
    assert conn.assigns.current_staff_user.id == user.id
    assert conn.assigns.current_staff_user.status == :active
    assert conn.assigns.current_staff_user.system_admin == false
  end

  test "wrong passwords do not create a staff session", %{conn: conn} do
    user = create_staff_user!()
    {view, form} = sign_in_form(conn, user.email, "incorrect passphrase")

    html = render_submit(form)
    failure = follow_trigger_action(form, conn)

    assert html =~ "phx-trigger-action"
    assert failure.status == 401
    assert failure.resp_body == "Authentication failed"
    assert view |> element("form") |> render() =~ "Password"

    conn = get(recycle(conn), "/admin")
    assert redirected_to(conn) == "/admin/sign-in"
  end

  test "suspended staff cannot authenticate", %{conn: conn} do
    user = create_staff_user!()
    transition_staff_user!(user, :suspended)
    {view, form} = sign_in_form(conn, user.email, @password)

    assert render_submit(form) =~ "phx-trigger-action"
    failure = follow_trigger_action(form, conn)
    assert failure.status == 401
    assert failure.resp_body == "Authentication failed"
    assert view |> element("form") |> render() =~ "Password"

    conn = get(recycle(conn), "/admin")
    assert redirected_to(conn) == "/admin/sign-in"
  end

  test "disabled staff cannot authenticate", %{conn: conn} do
    user = create_staff_user!()
    transition_staff_user!(user, :disabled)
    {view, form} = sign_in_form(conn, user.email, @password)

    assert render_submit(form) =~ "phx-trigger-action"
    failure = follow_trigger_action(form, conn)
    assert failure.status == 401
    assert failure.resp_body == "Authentication failed"
    assert view |> element("form") |> render() =~ "Password"

    conn = get(recycle(conn), "/admin")
    assert redirected_to(conn) == "/admin/sign-in"
  end

  test "authenticated requests resolve current_staff_user on the server", %{conn: conn} do
    user = create_staff_user!()
    conn = authenticate(conn, user.email)

    conn = conn |> recycle() |> get("/admin")

    assert conn.assigns.current_staff_user.id == user.id
    assert conn.assigns.current_staff_user.email == user.email
  end

  test "the session stores identity only and refreshes SYSTEM_ADMIN from PostgreSQL", %{
    conn: conn
  } do
    user = create_staff_user!()
    conn = authenticate(conn, user.email)
    session = get_session(conn)

    assert (Map.get(session, :staffuser) || Map.get(session, "staffuser")) ==
             AshAuthentication.user_to_subject(user)

    refute Map.has_key?(session, "system_admin")
    refute Map.has_key?(session, "status")

    conn = conn |> recycle() |> get("/admin")
    assert conn.assigns.current_staff_user.system_admin == false

    Repo.query!("UPDATE staff_users SET system_admin = TRUE WHERE id = $1::uuid", [
      Ecto.UUID.dump!(user.id)
    ])

    conn = conn |> recycle() |> get("/admin")

    assert conn.assigns.current_staff_user.system_admin == true
  end

  test "an existing session loses access after staff status becomes suspended", %{conn: conn} do
    user = create_staff_user!()
    conn = authenticate(conn, user.email)
    transition_staff_user!(user, :suspended)

    conn = conn |> recycle() |> get("/admin")

    assert redirected_to(conn) == "/admin/sign-in"
    assert conn.assigns.current_staff_user == nil
  end

  test "an existing session loses access after staff status becomes disabled", %{conn: conn} do
    user = create_staff_user!()
    conn = authenticate(conn, user.email)
    transition_staff_user!(user, :disabled)

    conn = conn |> recycle() |> get("/admin")

    assert redirected_to(conn) == "/admin/sign-in"
    assert conn.assigns.current_staff_user == nil
  end

  test "logout requires a CSRF-protected DELETE and invalidates the browser session", %{
    conn: conn
  } do
    user = create_staff_user!()
    conn = authenticate(conn, user.email)

    sign_out_routes =
      Router.__routes__()
      |> Enum.filter(&(&1.path == "/admin/sign-out"))
      |> Enum.map(& &1.verb)

    assert Enum.sort(sign_out_routes) == [:delete, :get]

    confirmation = conn |> recycle() |> get("/admin/sign-out")
    assert confirmation.status == 200
    assert confirmation.resp_body =~ "name=\"_csrf_token\""
    assert confirmation.resp_body =~ ~r/name="_method" type="hidden" hidden value="delete"/
    assert get(recycle(confirmation), "/admin").status == 204

    csrf_token =
      Regex.run(
        ~r/name="_csrf_token" type="hidden" hidden value="([^"]+)"/,
        confirmation.resp_body
      )
      |> Enum.at(1)

    signed_out =
      confirmation
      |> recycle()
      |> delete("/admin/sign-out", %{"_csrf_token" => csrf_token})

    assert redirected_to(signed_out) == "/admin/sign-in"

    denied = signed_out |> recycle() |> get("/admin")
    assert redirected_to(denied) == "/admin/sign-in"
  end

  test "credentials and password hashes never enter the session, response, or logs", %{conn: conn} do
    user = create_staff_user!()

    assert %Postgrex.Result{rows: [[password_hash]]} =
             Repo.query!("SELECT hashed_password FROM staff_users WHERE id = $1::uuid", [
               Ecto.UUID.dump!(user.id)
             ])

    {conn, logs} =
      capture_log(fn ->
        conn = authenticate(conn, user.email)
        send(self(), {:authenticated_conn, conn})
      end)
      |> then(fn logs ->
        receive do
          {:authenticated_conn, authenticated_conn} -> {authenticated_conn, logs}
        end
      end)

    response = Enum.join(get_resp_header(conn, "set-cookie"), "\n") <> conn.resp_body
    session = get_session(conn)

    refute response =~ @password
    refute response =~ password_hash
    refute inspect(session) =~ @password
    refute inspect(session) =~ password_hash
    refute logs =~ @password
    refute logs =~ password_hash
  end

  test "the staff boundary allows active staff without checking SYSTEM_ADMIN", %{conn: conn} do
    user = create_staff_user!()
    conn = authenticate(conn, user.email)

    conn = conn |> recycle() |> get("/admin")

    assert conn.status == 204
    assert conn.assigns.current_staff_user.system_admin == false
  end

  test "local session cookies are HTTP-only and use SameSite=Lax", %{conn: conn} do
    user = create_staff_user!()
    conn = authenticate(conn, user.email)
    cookie = Enum.join(get_resp_header(conn, "set-cookie"), ";")

    assert cookie =~ "HttpOnly"
    assert cookie =~ "SameSite=Lax"
    refute cookie =~ "; Secure"
  end

  defp sign_in_form(conn, email, password) do
    {:ok, view, _html} = live(conn, "/admin/sign-in")

    form =
      form(view, @sign_in_form, %{
        "staffuser" => %{"email" => to_string(email), "password" => password}
      })

    {view, form}
  end

  defp authenticate(conn, email) do
    {_view, form} = sign_in_form(conn, email, @password)
    assert render_submit(form) =~ "phx-trigger-action"
    conn = follow_trigger_action(form, conn)
    assert redirected_to(conn) == "/admin"
    conn
  end

  defp create_staff_user!(attrs \\ []) do
    email = "staff-#{System.unique_integer([:positive])}@example.com"

    attrs =
      Enum.into(attrs, %{email: email, password: @password, password_confirmation: @password})

    StaffUser
    |> Ash.Changeset.for_create(:provision_staff_user, attrs)
    |> Ash.create!(authorize?: false)
  end

  defp transition_staff_user!(user, :suspended) do
    admin = create_system_admin!()
    assert {:ok, suspended_user} = Accounts.suspend_staff_user(user, actor: admin)
    assert suspended_user.status == :suspended
  end

  defp transition_staff_user!(user, :disabled) do
    admin = create_system_admin!()
    assert {:ok, disabled_user} = Accounts.disable_staff_user(user, actor: admin)
    assert disabled_user.status == :disabled
  end

  defp create_system_admin! do
    user = create_staff_user!()

    assert %Postgrex.Result{num_rows: 1} =
             Repo.query!("UPDATE staff_users SET system_admin = TRUE WHERE id = $1::uuid", [
               Ecto.UUID.dump!(user.id)
             ])

    Repo.get!(StaffUser, user.id)
  end
end
