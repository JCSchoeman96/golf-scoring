defmodule GolfScoringWeb.Admin.RoundSetupLiveTest do
  use GolfScoringWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Competition
  alias GolfScoring.Competition.Event
  alias GolfScoring.GolfCatalog
  alias GolfScoring.Repo

  @password "GLS-14 synthetic staff passphrase 2026"
  @sign_in_form "#staffuser-password-sign-in-with-password"

  setup do
    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    :ok
  end

  test "Event Admin can configure route and snapshot tee profiles", %{conn: conn} do
    setup = seed_round_setup!()
    conn = authenticate(conn, setup.admin.email)

    {:ok, view, _html} =
      live(conn, ~p"/admin/events/#{setup.event.id}/rounds/#{setup.round.id}/setup")

    assert has_element?(view, "#round-setup")
    refute render(view) =~ "open_scoring"
    refute render(view) =~ "Open scoring"

    route_params =
      setup.holes
      |> Enum.with_index(1)
      |> Map.new(fn {hole, play_order} -> {"hole_#{play_order}", hole.id} end)

    render_submit(element(view, "#round-route-form"), %{"route" => route_params})

    assert has_element?(view, "#round-route-list")

    render_submit(element(view, "#round-snapshot-form"), %{
      "snapshot" => %{"profile_ids" => [setup.profile.id]}
    })

    assert render(view) =~ setup.profile.id
  end

  test "Competition Manager may access round setup", %{conn: conn} do
    setup = seed_round_setup!()
    manager = create_staff_user!()
    assign_role!(setup.admin, setup.event, manager, :competition_manager)
    conn = authenticate(conn, manager.email)

    {:ok, view, _html} =
      live(conn, ~p"/admin/events/#{setup.event.id}/rounds/#{setup.round.id}/setup")

    assert has_element?(view, "#round-snapshot-button")
  end

  test "registration staff is denied", %{conn: conn} do
    setup = seed_round_setup!()
    staff = create_staff_user!()
    assign_role!(setup.admin, setup.event, staff, :registration_staff)
    conn = authenticate(conn, staff.email)

    assert {:error, {:live_redirect, %{to: "/admin"}}} =
             live(conn, ~p"/admin/events/#{setup.event.id}/rounds/#{setup.round.id}/setup")
  end

  test "round/event URL mismatch is denied", %{conn: conn} do
    setup = seed_round_setup!()
    other_event = create_event!()
    conn = authenticate(conn, setup.admin.email)

    assert {:error, {:live_redirect, %{to: "/admin"}}} =
             live(conn, ~p"/admin/events/#{other_event.id}/rounds/#{setup.round.id}/setup")
  end

  test "malformed snapshot selection shows a controlled error", %{conn: conn} do
    setup = seed_round_setup!()
    conn = authenticate(conn, setup.admin.email)

    {:ok, view, _html} =
      live(conn, ~p"/admin/events/#{setup.event.id}/rounds/#{setup.round.id}/setup")

    html =
      render_submit(element(view, "#round-snapshot-form"), %{
        "snapshot" => %{"profile_ids" => ["not-a-uuid"]}
      })

    assert html =~ "valid"
  end

  test "stale Event Admin cannot mutate after assignment revocation", %{conn: conn} do
    setup = seed_round_setup!()
    conn = authenticate(conn, setup.admin.email)
    replacement = create_event_admin!(setup.event)

    {:ok, view, _html} =
      live(conn, ~p"/admin/events/#{setup.event.id}/rounds/#{setup.round.id}/setup")

    {:ok, _} =
      Accounts.revoke_event_staff_role(
        active_assignment(setup.event, setup.admin),
        actor: replacement
      )

    route_params =
      setup.holes
      |> Enum.with_index(1)
      |> Map.new(fn {hole, play_order} -> {"hole_#{play_order}", hole.id} end)

    html = render_submit(element(view, "#round-route-form"), %{"route" => route_params})
    assert html =~ "not allowed" or html =~ "Route save failed"
  end

  test "no scoring-open control is exposed", %{conn: conn} do
    setup = seed_round_setup!()
    conn = authenticate(conn, setup.admin.email)

    {:ok, view, html} =
      live(conn, ~p"/admin/events/#{setup.event.id}/rounds/#{setup.round.id}/setup")

    refute html =~ "open_scoring"
    refute has_element?(view, "[phx-click=\"open_scoring\"]")
  end

  defp seed_round_setup! do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    holes = create_eighteen_holes!(event, admin, course)
    tee_set = create_tee_set!(event, admin, course)
    profile = create_profile!(event, admin, tee_set, holes)
    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)

    %{event: event, admin: admin, round: round, holes: holes, profile: profile}
  end

  defp create_profile!(event, admin, tee_set, holes) do
    hole_ratings =
      Enum.map(holes, fn hole ->
        %{course_hole_id: hole.id, par: 4, stroke_index: hole.hole_number, distance_m: 300}
      end)

    {:ok, profile} =
      GolfCatalog.configure_tee_rating_profile(
        event.id,
        %{
          tee_set_id: tee_set.id,
          rating_label: "Men",
          course_rating: Decimal.new("72.0"),
          slope_rating: 113,
          total_par: 72,
          hole_ratings: hole_ratings
        },
        actor: admin
      )

    profile
  end

  defp create_tee_set!(event, admin, course) do
    {:ok, tee_set} =
      GolfCatalog.configure_tee_set(event.id, %{course_id: course.id, name: "White"},
        actor: admin
      )

    tee_set
  end

  defp create_eighteen_holes!(event, admin, course) do
    for n <- 1..18 do
      {:ok, hole} =
        GolfCatalog.configure_course_hole(
          event.id,
          %{course_id: course.id, hole_number: n},
          actor: admin
        )

      hole
    end
  end

  defp create_course!(event, admin) do
    {:ok, course} =
      GolfCatalog.create_course(event.id, %{name: "Course", location: "ZA"}, actor: admin)

    course
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
    email = "gls14-round-#{System.unique_integer([:positive])}@example.com"

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

  defp active_assignment(event, staff) do
    [[assignment_id]] =
      Repo.query!(
        "SELECT id::text FROM event_staff_assignments WHERE event_id = $1::uuid AND staff_user_id = $2::uuid AND role = 'event_admin' AND status = 'active'",
        [Ecto.UUID.dump!(event.id), Ecto.UUID.dump!(staff.id)]
      ).rows

    Accounts.EventStaffAssignment
    |> Ash.get!(assignment_id, authorize?: false)
  end
end
