defmodule GolfScoringWeb.Admin.CourseSetupLiveTest do
  use GolfScoringWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import Ecto.Query

  alias Decimal, as: D
  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Competition.Event
  alias GolfScoring.GolfCatalog.CourseHole
  alias GolfScoring.GolfCatalog.TeeRatingProfile
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

  test "LiveView persists exact tee rating facts from the form", %{conn: conn} do
    require Ash.Query
    event = create_event!()
    admin = create_event_admin!(event)
    conn = authenticate(conn, admin.email)

    {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/course-setup")

    render_submit(
      element(view, "#course-create-form"),
      %{"course" => %{"name" => "Persist Test", "location" => "ZA"}}
    )

    [[course_id_raw]] =
      Repo.query!("SELECT id::text FROM courses WHERE name = 'Persist Test' LIMIT 1").rows

    course_id = Ecto.UUID.cast!(course_id_raw)
    render_change(element(view, "#course-select-form"), %{"course_id" => course_id_raw})

    holes =
      for n <- 1..18 do
        render_submit(element(view, "#course-hole-form"), %{
          "hole" => %{"hole_number" => to_string(n)}
        })

        [[hole_id]] =
          Repo.query!(
            "SELECT id::text FROM course_holes WHERE course_id = $1::uuid AND hole_number = $2",
            [Ecto.UUID.dump!(course_id), n]
          ).rows

        %{hole_number: n, id: Ecto.UUID.cast!(hole_id)}
      end

    render_submit(element(view, "#tee-set-form"), %{"tee_set" => %{"name" => "Competition"}})

    [[tee_set_id]] =
      Repo.query!(
        "SELECT id::text FROM tee_sets WHERE course_id = $1::uuid AND name = 'Competition'",
        [Ecto.UUID.dump!(course_id)]
      ).rows

    tee_set_id = Ecto.UUID.cast!(tee_set_id)

    hole_facts = %{
      1 => %{par: 5, stroke_index: 11, distance_m: 487},
      2 => %{par: 3, stroke_index: 17, distance_m: 164},
      3 => %{par: 4, stroke_index: 1, distance_m: 401}
    }

    default_stroke_indices = [2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 15, 16, 18]

    default_par_stroke =
      4..18
      |> Enum.zip(default_stroke_indices)
      |> Map.new(fn {n, stroke_index} ->
        {n, %{par: 4, stroke_index: stroke_index, distance_m: 350 + n}}
      end)

    all_facts = Map.merge(default_par_stroke, hole_facts)

    total_par =
      all_facts
      |> Map.values()
      |> Enum.map(& &1.par)
      |> Enum.sum()

    hole_ratings_params =
      holes
      |> Map.new(fn hole ->
        fact = Map.fetch!(all_facts, hole.hole_number)

        {to_string(hole.id),
         %{
           "par" => to_string(fact.par),
           "stroke_index" => to_string(fact.stroke_index),
           "distance_m" => to_string(fact.distance_m)
         }}
      end)

    render_submit(element(view, "#tee-profile-form"), %{
      "tee_profile" => %{
        "tee_set_id" => tee_set_id,
        "rating_label" => "Competition White",
        "course_rating" => "70.8",
        "slope_rating" => "127",
        "total_par" => to_string(total_par),
        "hole_ratings" => hole_ratings_params
      }
    })

    profile =
      TeeRatingProfile
      |> Ash.Query.filter(tee_set_id == ^tee_set_id and rating_label == "Competition White")
      |> Ash.read_one!(authorize?: false)

    assert D.equal?(profile.course_rating, D.new("70.8"))
    assert profile.slope_rating == 127
    assert profile.total_par == total_par

    stored_by_hole =
      profile.hole_ratings
      |> Enum.map(fn rating ->
        {Ecto.UUID.cast!(rating.course_hole_id), rating}
      end)
      |> Map.new()

    for hole <- holes do
      expected = Map.fetch!(all_facts, hole.hole_number)
      stored = Map.fetch!(stored_by_hole, hole.id)

      assert stored.par == expected.par
      assert stored.stroke_index == expected.stroke_index
      assert stored.distance_m == expected.distance_m
    end
  end

  test "stale Event Admin cannot mutate catalog after assignment revocation", %{conn: conn} do
    event = create_event!()
    admin_a = create_event_admin!(event)
    admin_b = create_event_admin!(event)
    conn = authenticate(conn, admin_a.email)

    {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/course-setup")

    render_submit(
      element(view, "#course-create-form"),
      %{"course" => %{"name" => "Stale Guard", "location" => "ZA"}}
    )

    [[course_id]] =
      Repo.query!("SELECT id::text FROM courses WHERE name = 'Stale Guard' LIMIT 1").rows

    render_change(element(view, "#course-select-form"), %{"course_id" => course_id})

    holes_before =
      Repo.one!(
        from(h in CourseHole,
          where: h.course_id == ^Ecto.UUID.cast!(course_id),
          select: count(h.id)
        )
      )

    {:ok, _} =
      Accounts.revoke_event_staff_role(
        active_assignment(event, admin_a),
        actor: admin_b
      )

    render_submit(element(view, "#course-hole-form"), %{"hole" => %{"hole_number" => "99"}})

    holes_after =
      Repo.one!(
        from(h in CourseHole,
          where: h.course_id == ^Ecto.UUID.cast!(course_id),
          select: count(h.id)
        )
      )

    assert holes_after == holes_before
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

  defp active_assignment(event, staff) do
    [[assignment_id]] =
      Repo.query!(
        "SELECT id::text FROM event_staff_assignments WHERE event_id = $1::uuid AND staff_user_id = $2::uuid AND role = 'event_admin' AND status = 'active'",
        [Ecto.UUID.dump!(event.id), Ecto.UUID.dump!(staff.id)]
      ).rows

    Accounts.EventStaffAssignment
    |> Ash.get!(assignment_id, authorize?: false)
  end

  defp create_system_admin! do
    staff = create_staff_user!()

    Repo.query!("UPDATE staff_users SET system_admin = TRUE WHERE id = $1::uuid", [
      Ecto.UUID.dump!(staff.id)
    ])

    staff
  end
end
