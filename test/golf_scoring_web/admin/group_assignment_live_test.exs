defmodule GolfScoringWeb.Admin.GroupAssignmentLiveTest do
  use GolfScoringWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ash.Changeset
  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Competition
  alias GolfScoring.Competition.Event
  alias GolfScoring.Competition.RoundHole
  alias GolfScoring.Repo

  @password "GLS-18 synthetic staff passphrase 2026"
  @sign_in_form "#staffuser-password-sign-in-with-password"

  setup do
    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    :ok
  end

  test "Event Admin and Competition Manager can access group assignment", %{conn: conn} do
    setup = seed_group_setup!()
    conn = authenticate(conn, setup.admin.email)

    {:ok, view, _html} =
      live(conn, ~p"/admin/events/#{setup.event.id}/rounds/#{setup.round.id}/groups")

    assert has_element?(view, "#group-assignment")
    assert has_element?(view, "#create-playing-group-button")

    manager = create_staff_user!()
    assign_role!(setup.admin, setup.event, manager, :competition_manager)
    manager_conn = authenticate(build_conn(), manager.email)

    {:ok, manager_view, _} =
      live(manager_conn, ~p"/admin/events/#{setup.event.id}/rounds/#{setup.round.id}/groups")

    assert has_element?(manager_view, "#create-playing-group-button")
  end

  test "registration staff is denied", %{conn: conn} do
    setup = seed_group_setup!()
    staff = create_staff_user!()
    assign_role!(setup.admin, setup.event, staff, :registration_staff)
    conn = authenticate(conn, staff.email)

    assert {:error, {:live_redirect, %{to: "/admin"}}} =
             live(conn, ~p"/admin/events/#{setup.event.id}/rounds/#{setup.round.id}/groups")
  end

  test "creates group and assigns entry and start label 14A/14B", %{conn: conn} do
    setup = seed_group_setup!()
    conn = authenticate(conn, setup.admin.email)
    entry = add_entry!(setup)

    {:ok, view, _html} =
      live(conn, ~p"/admin/events/#{setup.event.id}/rounds/#{setup.round.id}/groups")

    render_click(element(view, "#create-playing-group-button"))
    html = render(view)
    assert html =~ "playing-group-"

    [group_id | _] =
      Regex.scan(~r/id="playing-group-([0-9a-f-]+)"/, html)
      |> Enum.map(fn [_, id] -> id end)

    render_submit(element(view, "#assign-entry-form-#{group_id}"), %{
      "assignment" => %{"entry_id" => entry.id, "group_id" => group_id}
    })

    assert has_element?(view, "#group-members-#{group_id}", entry.id)

    render_submit(element(view, "#assign-start-form-#{group_id}"), %{
      "start" => %{
        "group_id" => group_id,
        "round_hole_id" => setup.hole_14.id,
        "position" => "1"
      }
    })

    assert render(view) =~ "14A"

    render_submit(element(view, "#assign-start-form-#{group_id}"), %{
      "start" => %{
        "group_id" => group_id,
        "round_hole_id" => setup.hole_14.id,
        "position" => "2"
      }
    })

    refute render(view) =~ "14A"
    assert render(view) =~ "14B"
  end

  test "invalid UUID and position produce controlled errors", %{conn: conn} do
    setup = seed_group_setup!()
    conn = authenticate(conn, setup.admin.email)

    {:ok, view, _html} =
      live(conn, ~p"/admin/events/#{setup.event.id}/rounds/#{setup.round.id}/groups")

    render_click(element(view, "#create-playing-group-button"))
    html = render(view)

    [group_id | _] =
      Regex.scan(~r/id="playing-group-([0-9a-f-]+)"/, html)
      |> Enum.map(fn [_, id] -> id end)

    error_html =
      render_submit(element(view, "#assign-entry-form-#{group_id}"), %{
        "assignment" => %{"entry_id" => "not-a-uuid", "group_id" => group_id}
      })

    assert error_html =~ "valid"

    position_html =
      render_submit(element(view, "#assign-start-form-#{group_id}"), %{
        "start" => %{
          "group_id" => group_id,
          "round_hole_id" => setup.hole_14.id,
          "position" => "0"
        }
      })

    assert position_html =~ "valid"
  end

  test "post-open round rejects mutation from UI", %{conn: conn} do
    setup = seed_group_setup!()
    conn = authenticate(conn, setup.admin.email)

    Repo.query!("UPDATE rounds SET state = 'scoring_open' WHERE id = $1::uuid", [
      Ecto.UUID.dump!(setup.round.id)
    ])

    {:ok, view, _html} =
      live(conn, ~p"/admin/events/#{setup.event.id}/rounds/#{setup.round.id}/groups")

    refute has_element?(view, "#create-playing-group-button")
  end

  test "page does not reference ShotgunSlot", %{conn: conn} do
    setup = seed_group_setup!()
    conn = authenticate(conn, setup.admin.email)

    {:ok, _view, html} =
      live(conn, ~p"/admin/events/#{setup.event.id}/rounds/#{setup.round.id}/groups")

    refute html =~ "ShotgunSlot"
    refute html =~ "shotgun_slot"
  end

  defp seed_group_setup! do
    event = create_event!()
    admin = create_event_admin!(event)
    course = create_course!(event, admin)
    {:ok, round} = Competition.create_round(event.id, course.id, actor: admin)

    hole_14 =
      RoundHole
      |> Changeset.for_create(:insert_layout_row, %{
        round_id: round.id,
        course_id: course.id,
        course_hole_id: create_course_hole!(event, admin, course.id, 14).id,
        play_order: 1,
        display_hole_number: 14
      })
      |> Ash.create!(authorize?: false)

    %{event: event, admin: admin, round: round, hole_14: hole_14}
  end

  defp add_entry!(setup) do
    player =
      GolfScoring.Competition.Player
      |> Changeset.for_create(:create_internal, %{
        first_name: "Sam",
        surname: "Player#{System.unique_integer([:positive])}"
      })
      |> Ash.create!(authorize?: false)

    {:ok, entry} =
      Competition.add_round_entry(setup.event.id, setup.round.id, player.id, actor: setup.admin)

    entry
  end

  defp create_course_hole!(event, admin, course_id, n) do
    {:ok, hole} =
      GolfScoring.GolfCatalog.configure_course_hole(
        event.id,
        %{course_id: course_id, hole_number: n},
        actor: admin
      )

    hole
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
    |> Changeset.for_create(:create_internal, %{})
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
    email = "gls18-live-#{System.unique_integer([:positive])}@example.com"

    Accounts.StaffUser
    |> Changeset.for_create(:provision_staff_user, %{
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

  defp create_course!(event, admin) do
    {:ok, course} =
      GolfScoring.GolfCatalog.create_course(event.id, %{name: "Course", location: "ZA"},
        actor: admin
      )

    course
  end
end
