defmodule GolfScoring.GolfCatalog.CourseTest do
  use ExUnit.Case, async: false

  alias Ash.Resource.Info
  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Accounts.EventStaffAssignment
  alias GolfScoring.Competition.Event
  alias GolfScoring.GolfCatalog
  alias GolfScoring.GolfCatalog.Course
  alias GolfScoring.GolfCatalog.CourseHole
  alias GolfScoring.Repo

  @password "GLS-10 synthetic staff passphrase 2026"

  @forbidden_course_hole_fields ~w(
    par stroke_index distance course_rating slope_rating
    display_hole_number play_order score scoring tee_set_id tee_rating_profile_id
  )

  setup do
    Process.put(:gls10_email_prefix, "gls10-#{Ecto.UUID.generate()}")
    on_exit(fn -> Process.delete(:gls10_email_prefix) end)

    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  test "GolfCatalog domain is registered with Course and CourseHole" do
    assert Course in Ash.Domain.Info.resources(GolfCatalog)
    assert CourseHole in Ash.Domain.Info.resources(GolfCatalog)
    assert GolfScoring.GolfCatalog in Application.get_env(:golf_scoring, :ash_domains)
  end

  test "Course and CourseHole expose only the named catalog actions" do
    assert is_nil(Info.action(Course, :create))
    assert is_nil(Info.action(Course, :update))
    assert is_nil(Info.action(Course, :destroy))
    assert is_nil(Info.action(Course, :set_status))

    assert Info.action(Course, :create_course)
    assert Info.action(Course, :update_course)
    assert Info.action(Course, :archive_course)

    assert is_nil(Info.action(CourseHole, :create))
    assert is_nil(Info.action(CourseHole, :update))
    assert is_nil(Info.action(CourseHole, :destroy))

    assert Info.action(CourseHole, :configure_course_hole)
  end

  test "active EventAdmin can create, update, and archive a Course" do
    event = create_event!()
    admin = create_event_admin!(event)

    assert {:ok, course} =
             GolfCatalog.create_course(
               event.id,
               %{name: "Royal Example", location: "Exampleville"},
               actor: admin
             )

    assert course.status == :active
    assert course.name == "Royal Example"

    assert {:ok, updated} =
             GolfCatalog.update_course(
               course,
               event.id,
               %{name: "Royal Example GC", location: "Exampleville, ZA"},
               actor: admin
             )

    assert updated.name == "Royal Example GC"

    assert {:ok, archived} = GolfCatalog.archive_course(course, event.id, actor: admin)
    assert archived.status == :archived
  end

  test "archived Courses reject update_course" do
    event = create_event!()
    admin = create_event_admin!(event)

    {:ok, course} =
      GolfCatalog.create_course(
        event.id,
        %{name: "Archived Course", location: "Nowhere"},
        actor: admin
      )

    assert {:ok, archived} = GolfCatalog.archive_course(course, event.id, actor: admin)

    assert {:error, _error} =
             GolfCatalog.update_course(
               archived,
               event.id,
               %{name: "Changed", location: "Nowhere"},
               actor: admin
             )
  end

  test "SYSTEM_ADMIN without EventAdmin assignment cannot mutate the catalog" do
    event = create_event!()
    system_admin = create_system_admin!()

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.create_course(
               event.id,
               %{name: "Blocked", location: "Nowhere"},
               actor: system_admin
             )
  end

  test "wrong-event, revoked, suspended, disabled, and stale actor authority fail closed" do
    event = create_event!()
    other_event = create_event!()
    admin = create_event_admin!(event)
    cross_event_admin = create_event_admin!(other_event)

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.create_course(
               event.id,
               %{name: "Cross Event", location: "Nowhere"},
               actor: cross_event_admin
             )

    revoked_staff = create_event_admin!(event)

    assert {:ok, revoked} =
             Accounts.revoke_event_staff_role(
               active_assignment_record(event, revoked_staff),
               actor: admin
             )

    assert revoked.status == :revoked

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.create_course(
               event.id,
               %{name: "Revoked", location: "Nowhere"},
               actor: revoked_staff
             )

    suspended_admin = create_event_admin!(event)
    stale_suspended = set_staff_status!(suspended_admin, :suspended)

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.create_course(
               event.id,
               %{name: "Suspended", location: "Nowhere"},
               actor: stale_suspended
             )

    disabled_admin = create_event_admin!(event)
    stale_disabled = set_staff_status!(disabled_admin, :disabled)

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.create_course(
               event.id,
               %{name: "Disabled", location: "Nowhere"},
               actor: stale_disabled
             )

    stale_active_struct = admin
    replacement = create_event_admin!(event)

    assert {:ok, _} =
             Accounts.revoke_event_staff_role(
               active_assignment_record(event, admin),
               actor: replacement
             )

    assert stale_active_struct.status == :active

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.create_course(
               event.id,
               %{name: "Stale Assignment", location: "Nowhere"},
               actor: stale_active_struct
             )
  end

  test "CourseHole enforces Course ownership and per-course hole uniqueness" do
    event = create_event!()
    admin = create_event_admin!(event)

    {:ok, course_a} =
      GolfCatalog.create_course(event.id, %{name: "Course A", location: "A"}, actor: admin)

    {:ok, course_b} =
      GolfCatalog.create_course(event.id, %{name: "Course B", location: "B"}, actor: admin)

    assert {:ok, hole_a_1} =
             GolfCatalog.configure_course_hole(
               event.id,
               %{course_id: course_a.id, hole_number: 1},
               actor: admin
             )

    assert hole_a_1.course_id == course_a.id

    assert {:ok, hole_b_1} =
             GolfCatalog.configure_course_hole(
               event.id,
               %{course_id: course_b.id, hole_number: 1},
               actor: admin
             )

    assert hole_b_1.id != hole_a_1.id

    assert {:ok, same_hole} =
             GolfCatalog.configure_course_hole(
               event.id,
               %{course_id: course_a.id, hole_number: 1},
               actor: admin
             )

    assert same_hole.id == hole_a_1.id

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "INSERT INTO course_holes (course_id, hole_number) VALUES ($1::uuid, 1)",
        [Ecto.UUID.dump!(course_a.id)]
      )
    end
  end

  test "CourseHole rejects non-positive hole numbers and accepts hole numbers above 18" do
    event = create_event!()
    admin = create_event_admin!(event)

    {:ok, course} =
      GolfCatalog.create_course(event.id, %{name: "Long Course", location: "Links"}, actor: admin)

    assert {:error, _error} =
             GolfCatalog.configure_course_hole(
               event.id,
               %{course_id: course.id, hole_number: 0},
               actor: admin
             )

    assert {:ok, hole_27} =
             GolfCatalog.configure_course_hole(
               event.id,
               %{course_id: course.id, hole_number: 27},
               actor: admin
             )

    assert hole_27.hole_number == 27
  end

  test "CourseHole schema exposes only physical identity fields" do
    attribute_names =
      CourseHole
      |> Info.attributes()
      |> Enum.map(& &1.name)
      |> Enum.map(&Atom.to_string/1)

    refute Enum.any?(@forbidden_course_hole_fields, &(&1 in attribute_names))

    assert Enum.sort(attribute_names) ==
             Enum.sort(~w(id course_id hole_number inserted_at updated_at))
  end

  test "PostgreSQL preserves catalog history with restrict foreign keys" do
    event = create_event!()
    admin = create_event_admin!(event)

    {:ok, course} =
      GolfCatalog.create_course(event.id, %{name: "Protected", location: "Safe"}, actor: admin)

    assert {:ok, _} =
             GolfCatalog.configure_course_hole(
               event.id,
               %{course_id: course.id, hole_number: 3},
               actor: admin
             )

    assert_raise Postgrex.Error, fn ->
      Repo.query!("DELETE FROM courses WHERE id = $1::uuid", [Ecto.UUID.dump!(course.id)])
    end
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

  defp active_assignment_record(event, staff) do
    [[assignment_id]] =
      Repo.query!(
        "SELECT id::text FROM event_staff_assignments WHERE event_id = $1::uuid AND staff_user_id = $2::uuid AND role = 'event_admin' AND status = 'active'",
        [Ecto.UUID.dump!(event.id), Ecto.UUID.dump!(staff.id)]
      ).rows

    EventStaffAssignment
    |> Ash.get!(assignment_id, authorize?: false)
  end

  defp create_staff_user! do
    email =
      "#{Process.get(:gls10_email_prefix)}-#{System.unique_integer([:positive])}@example.com"

    GolfScoring.Accounts.StaffUser
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

    Repo.get!(GolfScoring.Accounts.StaffUser, staff.id)
  end

  defp set_staff_status!(staff, status) do
    Repo.query!("UPDATE staff_users SET status = $1 WHERE id = $2::uuid", [
      Atom.to_string(status),
      Ecto.UUID.dump!(staff.id)
    ])

    Repo.get!(GolfScoring.Accounts.StaffUser, staff.id)
  end
end
