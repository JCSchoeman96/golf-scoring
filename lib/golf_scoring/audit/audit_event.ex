defmodule GolfScoring.Audit.AuditEvent do
  @moduledoc "Append-only record of a structured operational event."

  use Ash.Resource,
    domain: GolfScoring.Audit,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "audit_events"
    repo GolfScoring.Repo

    references do
      reference :actor_staff_user, on_delete: :restrict
    end

    custom_indexes do
      index :actor_staff_user_id, name: "audit_events_actor_staff_user_id_index"
      index [:target_type, :target_id], name: "audit_events_target_index"
      index :occurred_at, name: "audit_events_occurred_at_index"
    end
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :record_staff_event do
      public? false

      accept [
        :actor_staff_user_id,
        :action,
        :target_type,
        :target_id,
        :context,
        :changes,
        :reason
      ]

      validate present(:actor_staff_user_id)
      validate {GolfScoring.Audit.Validations.NoSensitiveData, []}
    end

    create :record_system_event do
      public? false

      accept [
        :action,
        :target_type,
        :target_id,
        :context,
        :changes,
        :reason
      ]

      validate {GolfScoring.Audit.Validations.NoSensitiveData, []}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :action, :string do
      allow_nil? false
    end

    attribute :target_type, :string do
      allow_nil? false
    end

    attribute :target_id, :uuid do
      allow_nil? false
    end

    attribute :context, :map do
      allow_nil? false
      default %{}
    end

    attribute :changes, :map do
      allow_nil? false
      default %{}
    end

    attribute :reason, :string

    create_timestamp :occurred_at
  end

  relationships do
    belongs_to :actor_staff_user, GolfScoring.Accounts.StaffUser do
      allow_nil? true
      public? false
    end
  end
end
