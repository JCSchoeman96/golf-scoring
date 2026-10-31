defmodule GolfScoringWeb.Admin.CourseSetupLiveTest do
  use GolfScoringWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Competition.Event
  alias GolfScoring.Repo

  @password "GLS-14 synthetic staff passphrase 2026"
  @sign_in_form "#staffuser-password-sign-in-with-password"

  setup do
    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    :ok
  end

  test "active Event Admin can reach course setup and create catalog data", %{conn: conn} do
    event = create_event!()
    admin = create_event_admin!(event)
    conn = authenticate(conn, admin.email)

    {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/course-setup")
    assert has_element?(view, "#course-setup")

    render_submit(
      element(view, "#course-create-form"),
      %{"course" => %{"name" => "Royal Test", "location" => "ZA"}}
    )

    [[course_id]] =
      Repo.query!("SELECT id::text FROM courses WHERE name = 'Royal Test' LIMIT 1").rows

    render_change(element(view, "#course-select-form"), %{"course_id" => course_id})

    render_submit(element(view, "#course-hole-form"), %{"hole" => %{"hole_number" => "1"}})
    assert has_element?(view, "#course-hole-list")

    render_submit(element(view, "#tee-set-form"), %{"tee_set" => %{"name" => "White"}})
    assert render(view) =~ "White"
  end

  test "Competition Manager without Event Admin cannot mutate catalog", %{conn: conn} do
    event = create_event!()
    admin = create_event_admin!(event)
    manager = create_staff_user!()
    assign_role!(admin, event, manager, :competition_manager)
    conn = authenticate(conn, manager.email)

    assert {:error, {:live_redirect, %{to: "/admin"}}} =
             live(conn, ~p"/admin/events/#{event.id}/course-setup")
  end

  test "SYSTEM_ADMIN without Event assignment is denied", %{conn: conn} do
    event = create_event!()
    _admin = create_event_admin!(event)
    system_admin = create_system_admin!()
    conn = authenticate(conn, system_admin.email)

    assert {:error, {:live_redirect, %{to: "/admin"}}} =
             live(conn, ~p"/admin/events/#{event.id}/course-setup")
  end

  test "unauthenticated users are redirected to sign-in", %{conn: conn} do
    event = create_event!()
    conn = get(conn, ~p"/admin/events/#{event.id}/course-setup")
    assert redirected_to(conn) == "/admin/sign-in"
  end

  defp authenticate(conn, email) do
    {:ok, view, _html} = live(conn, "/admin/sign-in")

    form =
      form(view, @sign_in_form, %{
        "staffuser" => %{"email" => to_string(email), "password" => @password}
      })

    render_submit(form)
    follow_trigger_action(form, conn)
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
    email = "gls14-web-#{System.unique_integer([:positive])}@example.com"

    GolfScoring.Accounts.StaffUser
    |> Ash.Changeset.for_create(:provision_staff_user, %{
      email: email,
      password: @password,
      password_confirmation: @password
    })
    |> Ash.create!(authorize?: false)
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

    staff
  end
end
