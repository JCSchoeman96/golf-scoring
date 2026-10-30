defmodule GolfScoring.GolfCatalog.TeeRatingProfileTest do
  use ExUnit.Case, async: false

  alias Ash.Resource.Info
  alias Decimal, as: D
  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts
  alias GolfScoring.Accounts.EventStaffAssignment
  alias GolfScoring.Competition.Event
  alias GolfScoring.GolfCatalog
  alias GolfScoring.GolfCatalog.TeeRatingProfile
  alias GolfScoring.GolfCatalog.TeeSet
  alias GolfScoring.Repo

  @password "GLS-11 synthetic staff passphrase 2026"

  setup do
    Process.put(:gls11_email_prefix, "gls11-#{Ecto.UUID.generate()}")
    on_exit(fn -> Process.delete(:gls11_email_prefix) end)

    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  test "GolfCatalog registers TeeSet and TeeRatingProfile with named actions only" do
    assert TeeSet in Ash.Domain.Info.resources(GolfCatalog)
    assert TeeRatingProfile in Ash.Domain.Info.resources(GolfCatalog)

    assert Info.action(TeeSet, :configure_tee_set)
    assert Info.action(TeeRatingProfile, :configure_tee_rating_profile)

    assert is_nil(Info.action(TeeSet, :create))
    assert is_nil(Info.action(TeeSet, :update))
    assert is_nil(Info.action(TeeSet, :destroy))
    assert is_nil(Info.action(TeeRatingProfile, :create))
    assert is_nil(Info.action(TeeRatingProfile, :update))
    assert is_nil(Info.action(TeeRatingProfile, :destroy))
  end

  test "active EventAdmin can configure TeeSet physical identity on an active Course" do
    event = create_event!()
    admin = create_event_admin!(event)

    {:ok, course} =
      GolfCatalog.create_course(event.id, %{name: "Royal Example", location: "ZA"}, actor: admin)

    assert {:ok, tee_set} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "White"},
               actor: admin
             )

    assert tee_set.course_id == course.id
    assert tee_set.name == "White"

    assert {:ok, same} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "White"},
               actor: admin
             )

    assert same.id == tee_set.id
  end

  test "archived Course rejects configure_tee_set using durable database state" do
    event = create_event!()
    admin = create_event_admin!(event)

    {:ok, course} =
      GolfCatalog.create_course(event.id, %{name: "Archived Links", location: "ZA"}, actor: admin)

    assert {:ok, archived} = GolfCatalog.archive_course(course, event.id, actor: admin)

    assert {:error, _error} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: archived.id, name: "Blue"},
               actor: admin
             )
  end

  test "TeeSet schema retains only physical tee identity fields" do
    attribute_names =
      TeeSet
      |> Info.attributes()
      |> Enum.map(& &1.name)
      |> Enum.map(&Atom.to_string/1)

    refute "course_rating" in attribute_names
    refute "slope_rating" in attribute_names
    refute "total_par" in attribute_names
    refute "gender" in attribute_names

    assert Enum.sort(attribute_names) ==
             Enum.sort(~w(id course_id name inserted_at updated_at))
  end

  test "active EventAdmin can configure TeeRatingProfile rating facts" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, holes} = course_with_tee_and_holes!(event, admin, hole_numbers: [1, 2, 3])

    hole_ratings =
      Enum.map(holes, fn hole ->
        %{
          course_hole_id: hole.id,
          par: 4,
          stroke_index: hole.hole_number,
          distance_mm: 350_000 + hole.hole_number * 1_000
        }
      end)

    assert {:ok, profile} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               %{
                 tee_set_id: tee_set.id,
                 rating_label: "Standard",
                 course_rating: D.new("72.4"),
                 slope_rating: 130,
                 total_par: 12,
                 hole_ratings: hole_ratings
               },
               actor: admin
             )

    assert profile.rating_label == "Standard"
    assert D.equal?(profile.course_rating, D.new("72.4"))
    assert profile.slope_rating == 130
    assert profile.total_par == 12
    assert length(profile.hole_ratings) == 3
    assert hd(profile.hole_ratings).distance_mm == 351_000
  end

  test "two rating profiles on the same TeeSet persist independent rating facts" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, holes} = course_with_tee_and_holes!(event, admin, hole_numbers: [1, 2])

    base_hole = fn hole, par, si, distance_mm ->
      %{
        course_hole_id: hole.id,
        par: par,
        stroke_index: si,
        distance_mm: distance_mm
      }
    end

    [hole_1, hole_2] = holes

    assert {:ok, profile_a} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               %{
                 tee_set_id: tee_set.id,
                 rating_label: "Context A",
                 course_rating: D.new("71.0"),
                 slope_rating: 125,
                 total_par: 8,
                 hole_ratings: [
                   base_hole.(hole_1, 4, 1, 350_000),
                   base_hole.(hole_2, 4, 2, 360_000)
                 ]
               },
               actor: admin
             )

    assert {:ok, profile_b} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               %{
                 tee_set_id: tee_set.id,
                 rating_label: "Context B",
                 course_rating: D.new("73.2"),
                 slope_rating: 138,
                 total_par: 9,
                 hole_ratings: [
                   base_hole.(hole_1, 5, 2, 380_000),
                   base_hole.(hole_2, 4, 1, 340_000)
                 ]
               },
               actor: admin
             )

    assert profile_a.id != profile_b.id
    assert D.equal?(profile_a.course_rating, D.new("71.0"))
    assert D.equal?(profile_b.course_rating, D.new("73.2"))
    assert hd(profile_a.hole_ratings).par == 4
    assert hd(profile_b.hole_ratings).par == 5
  end

  test "mixed-tee catalog holds independent TeeSets and rating profiles" do
    event = create_event!()
    admin = create_event_admin!(event)

    {:ok, course} =
      GolfCatalog.create_course(event.id, %{name: "Mixed Layout", location: "ZA"}, actor: admin)

    {:ok, white} =
      GolfCatalog.configure_tee_set(event.id, %{course_id: course.id, name: "White"},
        actor: admin
      )

    {:ok, blue} =
      GolfCatalog.configure_tee_set(event.id, %{course_id: course.id, name: "Blue"}, actor: admin)

    {:ok, hole} =
      GolfCatalog.configure_course_hole(
        event.id,
        %{course_id: course.id, hole_number: 1},
        actor: admin
      )

    assert {:ok, white_profile} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               profile_params(white.id, "White Standard", "70.1", 120, 4, hole),
               actor: admin
             )

    assert {:ok, blue_profile} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               profile_params(blue.id, "Blue Standard", "72.8", 135, 4, hole),
               actor: admin
             )

    assert white_profile.tee_set_id == white.id
    assert blue_profile.tee_set_id == blue.id
    assert white_profile.id != blue_profile.id
  end

  test "duplicate rating profile identity for the same TeeSet is rejected at PostgreSQL" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, [hole | _]} = course_with_tee_and_holes!(event, admin, hole_numbers: [1])

    assert {:ok, _} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               profile_params(tee_set.id, "Duplicate Me", "71.0", 125, 4, hole),
               actor: admin
             )

    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        """
        INSERT INTO tee_rating_profiles
          (tee_set_id, rating_label, course_rating, slope_rating, total_par, hole_ratings)
        VALUES ($1::uuid, 'Duplicate Me', 71.0, 125, 4, '[]'::jsonb)
        """,
        [Ecto.UUID.dump!(tee_set.id)]
      )
    end
  end

  test "PostgreSQL rejects TeeSet rows referencing a nonexistent Course" do
    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        "INSERT INTO tee_sets (course_id, name) VALUES ($1::uuid, 'Ghost')",
        [Ecto.UUID.dump!(Ecto.UUID.generate())]
      )
    end
  end

  test "PostgreSQL rejects TeeRatingProfile rows referencing a nonexistent TeeSet" do
    assert_raise Postgrex.Error, fn ->
      Repo.query!(
        """
        INSERT INTO tee_rating_profiles
          (tee_set_id, rating_label, course_rating, slope_rating, total_par, hole_ratings)
        VALUES ($1::uuid, 'Orphan', 70.0, 120, 72, '[]'::jsonb)
        """,
        [Ecto.UUID.dump!(Ecto.UUID.generate())]
      )
    end
  end

  test "configure_tee_rating_profile rejects CourseHole from another Course" do
    event = create_event!()
    admin = create_event_admin!(event)

    {:ok, course_a} =
      GolfCatalog.create_course(event.id, %{name: "Course A", location: "A"}, actor: admin)

    {:ok, course_b} =
      GolfCatalog.create_course(event.id, %{name: "Course B", location: "B"}, actor: admin)

    {:ok, tee_set_a} =
      GolfCatalog.configure_tee_set(event.id, %{course_id: course_a.id, name: "White"},
        actor: admin
      )

    {:ok, hole_b} =
      GolfCatalog.configure_course_hole(
        event.id,
        %{course_id: course_b.id, hole_number: 1},
        actor: admin
      )

    assert {:error, _error} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               %{
                 tee_set_id: tee_set_a.id,
                 rating_label: "Cross Course",
                 course_rating: D.new("71.0"),
                 slope_rating: 125,
                 total_par: 4,
                 hole_ratings: [
                   %{course_hole_id: hole_b.id, par: 4, stroke_index: 1, distance_mm: 350_000}
                 ]
               },
               actor: admin
             )
  end

  test "configure_tee_rating_profile rejects duplicate hole entries in one profile" do
    event = create_event!()
    admin = create_event_admin!(event)
    {_course, tee_set, [hole | _]} = course_with_tee_and_holes!(event, admin, hole_numbers: [1])

    assert {:error, _error} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               %{
                 tee_set_id: tee_set.id,
                 rating_label: "Dup Holes",
                 course_rating: D.new("71.0"),
                 slope_rating: 125,
                 total_par: 8,
                 hole_ratings: [
                   %{course_hole_id: hole.id, par: 4, stroke_index: 1, distance_mm: 350_000},
                   %{course_hole_id: hole.id, par: 5, stroke_index: 2, distance_mm: 360_000}
                 ]
               },
               actor: admin
             )
  end

  test "wrong-event, revoked, suspended, disabled, stale actor, and SYSTEM_ADMIN-only fail closed" do
    event = create_event!()
    other_event = create_event!()
    admin = create_event_admin!(event)
    cross_event_admin = create_event_admin!(other_event)

    {:ok, course} =
      GolfCatalog.create_course(event.id, %{name: "Protected", location: "ZA"}, actor: admin)

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "Blocked"},
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
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "Revoked"},
               actor: revoked_staff
             )

    system_admin = create_system_admin!()

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "System Only"},
               actor: system_admin
             )

    suspended_admin = create_event_admin!(event)
    stale_suspended = set_staff_status!(suspended_admin, :suspended)

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "Suspended"},
               actor: stale_suspended
             )

    disabled_admin = create_event_admin!(event)
    stale_disabled = set_staff_status!(disabled_admin, :disabled)

    assert {:error, %Ash.Error.Forbidden{}} =
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "Disabled"},
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
             GolfCatalog.configure_tee_set(
               event.id,
               %{course_id: course.id, name: "Stale Assignment"},
               actor: stale_active_struct
             )
  end

  test "PostgreSQL preserves catalog history with restrict foreign keys on tee catalog tables" do
    event = create_event!()
    admin = create_event_admin!(event)
    {course, tee_set, [hole | _]} = course_with_tee_and_holes!(event, admin, hole_numbers: [1])

    assert {:ok, _profile} =
             GolfCatalog.configure_tee_rating_profile(
               event.id,
               profile_params(tee_set.id, "Protected", "71.0", 125, 4, hole),
               actor: admin
             )

    assert_raise Postgrex.Error, fn ->
      Repo.query!("DELETE FROM courses WHERE id = $1::uuid", [Ecto.UUID.dump!(course.id)])
    end

    assert_raise Postgrex.Error, fn ->
      Repo.query!("DELETE FROM tee_sets WHERE id = $1::uuid", [Ecto.UUID.dump!(tee_set.id)])
    end
  end

  defp profile_params(tee_set_id, label, course_rating, slope_rating, total_par, hole) do
    %{
      tee_set_id: tee_set_id,
      rating_label: label,
      course_rating: D.new(course_rating),
      slope_rating: slope_rating,
      total_par: total_par,
      hole_ratings: [
        %{course_hole_id: hole.id, par: 4, stroke_index: 1, distance_mm: 350_000}
      ]
    }
  end

  defp course_with_tee_and_holes!(event, admin, opts) do
    hole_numbers = Keyword.fetch!(opts, :hole_numbers)

    {:ok, course} =
      GolfCatalog.create_course(
        event.id,
        %{name: "Course #{System.unique_integer([:positive])}", location: "ZA"},
        actor: admin
      )

    {:ok, tee_set} =
      GolfCatalog.configure_tee_set(
        event.id,
        %{course_id: course.id, name: "White"},
        actor: admin
      )

    holes =
      Enum.map(hole_numbers, fn hole_number ->
        {:ok, hole} =
          GolfCatalog.configure_course_hole(
            event.id,
            %{course_id: course.id, hole_number: hole_number},
            actor: admin
          )

        hole
      end)

    {course, tee_set, holes}
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
      "#{Process.get(:gls11_email_prefix)}-#{System.unique_integer([:positive])}@example.com"

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
