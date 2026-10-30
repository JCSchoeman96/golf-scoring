defmodule GolfScoring.Audit.AuditEventTest do
  use GolfScoring.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Audit
  alias GolfScoring.Audit.AuditEvent
  alias GolfScoring.Repo

  @password "Audit staff passphrase 2026"

  test "AuditEvent is registered in the Audit domain" do
    audit_event = AuditEvent

    assert {:module, ^audit_event} = Code.ensure_loaded(audit_event)
    assert AuditEvent in Ash.Domain.Info.resources(Audit)
    assert GolfScoring.Accounts in Application.get_env(:golf_scoring, :ash_domains)
    assert Audit in Application.get_env(:golf_scoring, :ash_domains)
  end

  test "only defines private record and read actions" do
    record_action = Ash.Resource.Info.action(AuditEvent, :record_staff_event)
    read_action = Ash.Resource.Info.action(AuditEvent, :read)

    refute record_action.public?

    assert MapSet.new(record_action.accept) ==
             MapSet.new([
               :actor_staff_user_id,
               :action,
               :target_type,
               :target_id,
               :context,
               :changes,
               :reason
             ])

    refute :id in record_action.accept
    refute :occurred_at in record_action.accept
    refute read_action.public?
    assert is_nil(Ash.Resource.Info.action(AuditEvent, :create))
    assert is_nil(Ash.Resource.Info.action(AuditEvent, :update))
    assert is_nil(Ash.Resource.Info.action(AuditEvent, :destroy))
    refute Ash.Resource.Info.attribute(AuditEvent, :occurred_at).writable?
    assert is_nil(Ash.Resource.Info.attribute(AuditEvent, :updated_at))

    attribute_names = Enum.map(Ash.Resource.Info.attributes(AuditEvent), & &1.name)

    refute Enum.any?(
             [:actor_name, :actor_email, :actor_id, :round_entry_id],
             &(&1 in attribute_names)
           )
  end

  test "persists staff audit metadata as structured JSONB and generates a UTC occurrence time" do
    staff_user = create_staff_user!()

    context = %{
      "event_id" => Ecto.UUID.generate(),
      "facts" => [%{"source" => "manual", "hole" => 8}]
    }

    changes = %{
      "before" => %{"strokes" => 5},
      "after" => %{"strokes" => 4}
    }

    assert {:ok, event} =
             record_event(staff_user, %{context: context, changes: changes})

    assert {:ok, _uuid} = Ecto.UUID.cast(event.id)
    assert event.actor_staff_user_id == staff_user.id
    assert event.action == "score_corrected"
    assert event.target_type == "hole_result"
    assert {:ok, _uuid} = Ecto.UUID.cast(event.target_id)
    assert event.context == context
    assert event.changes == changes
    assert event.reason == "Correction approved by the scorer"
    assert %DateTime{time_zone: "Etc/UTC", microsecond: {_, 6}} = event.occurred_at

    assert %Postgrex.Result{rows: [[^context, ^changes]]} =
             Repo.query!(
               "SELECT context, changes FROM audit_events WHERE id = $1::uuid",
               [Ecto.UUID.dump!(event.id)]
             )

    assert %Postgrex.Result{rows: [["changes", "jsonb"], ["context", "jsonb"]]} =
             Repo.query!("""
             SELECT column_name, data_type
             FROM information_schema.columns
             WHERE table_schema = 'public'
               AND table_name = 'audit_events'
               AND column_name IN ('context', 'changes')
             ORDER BY column_name
             """)
  end

  test "requires the staff actor and the action target metadata" do
    staff_user = create_staff_user!()

    for field <- [:actor_staff_user_id, :action, :target_type, :target_id] do
      assert {:error, _error} = record_event(staff_user, %{field => nil})
    end

    assert {:error, _error} = record_event(staff_user, %{}, [:actor_staff_user_id])
  end

  test "defaults context and changes to empty maps" do
    staff_user = create_staff_user!()

    assert {:ok, event} = record_event(staff_user, %{}, [:context, :changes])

    assert event.context == %{}
    assert event.changes == %{}

    assert %Postgrex.Result{rows: [[%{}, %{}]]} =
             Repo.query!("SELECT context, changes FROM audit_events WHERE id = $1::uuid", [
               Ecto.UUID.dump!(event.id)
             ])
  end

  test "rejects credential keys recursively in context and changes" do
    staff_user = create_staff_user!()

    for field <- [:context, :changes],
        key <- ["password", "PASSWORD_CONFIRMATION", :hashed_password] do
      unsafe_value = %{"outer" => [%{"credentials" => %{key => "must not persist"}}]}

      assert {:error, _error} = record_event(staff_user, %{field => unsafe_value})
    end
  end

  test "does not include staff passwords or hashes in ordinary audit results" do
    staff_user = create_staff_user!()
    assert {:ok, event} = record_event(staff_user)

    assert %Postgrex.Result{rows: [[hashed_password]]} =
             Repo.query!("SELECT hashed_password FROM staff_users WHERE id = $1::uuid", [
               Ecto.UUID.dump!(staff_user.id)
             ])

    refute Map.has_key?(event, :password)
    refute inspect(event) =~ @password
    refute inspect(event) =~ hashed_password
  end

  test "actor reference is nullable in PostgreSQL and restricts staff deletion" do
    assert %Postgrex.Result{rows: [["YES"]]} =
             Repo.query!("""
             SELECT is_nullable
             FROM information_schema.columns
             WHERE table_schema = 'public'
               AND table_name = 'audit_events'
               AND column_name = 'actor_staff_user_id'
             """)

    assert %Postgrex.Result{rows: [[nil, %NaiveDateTime{}]]} =
             Repo.query!(
               """
               INSERT INTO audit_events (action, target_type, target_id, context, changes)
               VALUES ('system_recovery', 'staff_user', $1, '{}', '{}')
               RETURNING actor_staff_user_id, occurred_at
               """,
               [Ecto.UUID.dump!(Ecto.UUID.generate())]
             )

    staff_user = create_staff_user!()
    assert {:ok, _event} = record_event(staff_user)

    assert %Postgrex.Result{rows: [["r"]]} =
             Repo.query!("""
             SELECT c.confdeltype::text
             FROM pg_constraint c
             JOIN unnest(c.conkey) AS key(attnum) ON true
             JOIN pg_attribute a
               ON a.attrelid = c.conrelid
              AND a.attnum = key.attnum
             WHERE c.conrelid = 'audit_events'::regclass
               AND c.contype = 'f'
               AND a.attname = 'actor_staff_user_id'
             """)

    assert_raise Postgrex.Error, fn ->
      Repo.query!("DELETE FROM staff_users WHERE id = $1::uuid", [
        Ecto.UUID.dump!(staff_user.id)
      ])
    end
  end

  test "creates the actor, target, and occurrence-time indexes" do
    assert %Postgrex.Result{rows: rows} =
             Repo.query!("""
             SELECT indexdef
             FROM pg_indexes
             WHERE schemaname = 'public'
               AND tablename = 'audit_events'
             """)

    index_definitions = Enum.map(rows, fn [indexdef] -> indexdef end)

    assert Enum.any?(index_definitions, &String.contains?(&1, "(actor_staff_user_id)"))
    assert Enum.any?(index_definitions, &String.contains?(&1, "(target_type, target_id)"))
    assert Enum.any?(index_definitions, &String.contains?(&1, "(occurred_at)"))
  end

  test "PostgreSQL rejects null required audit fields" do
    columns = ["action", "target_type", "target_id", "context", "changes", "occurred_at"]

    values = [
      "score_corrected",
      "hole_result",
      Ecto.UUID.dump!(Ecto.UUID.generate()),
      %{},
      %{},
      DateTime.utc_now()
    ]

    Sandbox.unboxed_run(Repo, fn ->
      for {column, index} <- Enum.with_index(columns) do
        invalid_values = List.replace_at(values, index, nil)

        error =
          assert_raise Postgrex.Error, fn ->
            Repo.query!(
              """
              INSERT INTO audit_events (action, target_type, target_id, context, changes, occurred_at)
              VALUES ($1, $2, $3, $4, $5, $6)
              """,
              invalid_values
            )
          end

        assert error.postgres.code == :not_null_violation
        assert error.postgres.column == column
      end
    end)
  end

  defp record_event(staff_user, overrides \\ %{}, missing_fields \\ []) do
    attributes =
      Map.merge(
        %{
          actor_staff_user_id: staff_user.id,
          action: "score_corrected",
          target_type: "hole_result",
          target_id: Ecto.UUID.generate(),
          context: %{"round_id" => Ecto.UUID.generate()},
          changes: %{"before" => %{"strokes" => 5}, "after" => %{"strokes" => 4}},
          reason: "Correction approved by the scorer"
        },
        overrides
      )
      |> Map.drop(missing_fields)

    Audit.record_staff_event(attributes, authorize?: false)
  end

  defp create_staff_user! do
    attributes = %{
      email: "audit-#{System.unique_integer([:positive])}@example.com",
      password: @password,
      password_confirmation: @password
    }

    StaffUser
    |> Ash.Changeset.for_create(:provision_staff_user, attributes)
    |> Ash.create!(authorize?: false)
  end
end
