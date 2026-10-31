defmodule GolfScoring.Competition.RoundHoleTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Competition
  alias GolfScoring.Competition.Event
  alias GolfScoring.Competition.Services.ConfigureRoundLayout
  alias GolfScoring.GolfCatalog
  alias GolfScoring.Repo

  @password "GLS-15 synthetic staff passphrase 2026"

  setup do
    Process.put(:gls15_hole_prefix, "gls15h-#{Ecto.UUID.generate()}")
    on_exit(fn -> Process.delete(:gls15_hole_prefix) end)

    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    :ok
  end

  test "PostgreSQL composite Round/Course FK rejects mismatched course_id on an empty route" do
    event = create_event!()
    admin = create_event_admin!(event)
    course_a = create_course!(event, admin, "A")
    course_b = create_course!(event, admin, "B")
    [hole_b | _] = create_eighteen_holes!(event, admin, course_b)

    {:ok, round_a} = Competition.create_round(event.id, course_a.id, actor: admin)

    round_course_fk_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO round_holes (round_id, course_hole_id, course_id, play_order, display_hole_number)
          VALUES ($1::uuid, $2::uuid, $3::uuid, 40, 1)
          """,
          [
            Ecto.UUID.dump!(round_a.id),
            Ecto.UUID.dump!(hole_b.id),
            Ecto.UUID.dump!(course_b.id)
          ]
        )
      end

    assert round_course_fk_error.postgres.code == :foreign_key_violation
    assert round_course_fk_error.postgres.constraint == "round_holes_round_id_fkey"
  end

  test "PostgreSQL composite CourseHole/Course FK rejects mismatched course_id on an empty route" do
    event = create_event!()
    admin = create_event_admin!(event)
    course_a = create_course!(event, admin, "A")
    course_b = create_course!(event, admin, "B")
    [hole_b | _] = create_eighteen_holes!(event, admin, course_b)

    {:ok, round_a} = Competition.create_round(event.id, course_a.id, actor: admin)

    course_hole_fk_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO round_holes (round_id, course_hole_id, course_id, play_order, display_hole_number)
          VALUES ($1::uuid, $2::uuid, $3::uuid, 41, 1)
          """,
          [
            Ecto.UUID.dump!(round_a.id),
            Ecto.UUID.dump!(hole_b.id),
            Ecto.UUID.dump!(course_a.id)
          ]
        )
      end

    assert course_hole_fk_error.postgres.code == :foreign_key_violation
    assert course_hole_fk_error.postgres.constraint == "round_holes_course_hole_id_fkey"
  end

  test "PostgreSQL enforces route uniqueness, positive orders, and round state" do
    event = create_event!()
    admin = create_event_admin!(event)
    course_a = create_course!(event, admin, "A")
    holes_a = create_eighteen_holes!(event, admin, course_a)

    {:ok, round} = Competition.create_round(event.id, course_a.id, actor: admin)
    {:ok, _} = ConfigureRoundLayout.run(admin, round.id, Enum.map(holes_a, & &1.id))

    [[_round_hole_id, course_hole_id, play_order]] =
      Repo.query!(
        "SELECT id::text, course_hole_id::text, play_order FROM round_holes WHERE round_id = $1::uuid LIMIT 1",
        [Ecto.UUID.dump!(round.id)]
      ).rows

    duplicate_order_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO round_holes (round_id, course_hole_id, course_id, play_order, display_hole_number)
          VALUES ($1::uuid, $2::uuid, $3::uuid, $4, 99)
          """,
          [
            Ecto.UUID.dump!(round.id),
            Ecto.UUID.dump!(Ecto.UUID.generate()),
            Ecto.UUID.dump!(course_a.id),
            play_order
          ]
        )
      end

    assert duplicate_order_error.postgres.code == :unique_violation

    assert duplicate_order_error.postgres.constraint ==
             "round_holes_unique_play_order_per_round_index"

    duplicate_hole_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO round_holes (round_id, course_hole_id, course_id, play_order, display_hole_number)
          VALUES ($1::uuid, $2::uuid, $3::uuid, 99, 99)
          """,
          [
            Ecto.UUID.dump!(round.id),
            Ecto.UUID.dump!(course_hole_id),
            Ecto.UUID.dump!(course_a.id)
          ]
        )
      end

    assert duplicate_hole_error.postgres.code == :unique_violation

    assert duplicate_hole_error.postgres.constraint ==
             "round_holes_unique_course_hole_per_round_index"

    invalid_state_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          "INSERT INTO rounds (event_id, course_id, state) VALUES ($1::uuid, $2::uuid, 'open')",
          [
            Ecto.UUID.dump!(event.id),
            Ecto.UUID.dump!(course_a.id)
          ]
        )
      end

    assert invalid_state_error.postgres.constraint == "rounds_state_must_be_valid"

    invalid_play_order_error =
      assert_raise Postgrex.Error, fn ->
        Repo.query!(
          """
          INSERT INTO round_holes (round_id, course_hole_id, course_id, play_order, display_hole_number)
          VALUES ($1::uuid, $2::uuid, $3::uuid, 0, 1)
          """,
          [
            Ecto.UUID.dump!(round.id),
            Ecto.UUID.dump!(Ecto.UUID.generate()),
            Ecto.UUID.dump!(course_a.id)
          ]
        )
      end

    assert invalid_play_order_error.postgres.constraint ==
             "round_holes_play_order_must_be_positive"
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
    email =
      "#{Process.get(:gls15_hole_prefix)}-#{System.unique_integer([:positive])}@example.com"

    GolfScoring.Accounts.StaffUser
    |> Ash.Changeset.for_create(:provision_staff_user, %{
      email: email,
      password: @password,
      password_confirmation: @password
    })
    |> Ash.create!(authorize?: false)
  end

  defp create_course!(event, admin, suffix) do
    {:ok, course} =
      GolfCatalog.create_course(
        event.id,
        %{name: "Course #{suffix}", location: suffix},
        actor: admin
      )

    course
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
end
