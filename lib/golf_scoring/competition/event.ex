defmodule GolfScoring.Competition.Event do
  @moduledoc "An Event and its guarded lifecycle state."

  use Ash.Resource,
    domain: GolfScoring.Competition,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "events"
    repo GolfScoring.Repo

    check_constraints do
      check_constraint :state, "events_state_must_be_valid",
        check: "state IN ('draft', 'published', 'live', 'completed', 'archived', 'cancelled')",
        message: "must be a valid Event lifecycle state"
    end
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :create_internal do
      public? false
      accept []
      transaction? true
    end

    update :publish_event do
      public? false
      accept []
      transaction? true
      require_atomic? false
      atomic_upgrade? false
      change {GolfScoring.Competition.EventLifecycleGuard, operation: :publish_event}
    end

    update :mark_event_live do
      public? false
      accept []
      transaction? true
      require_atomic? false
      atomic_upgrade? false
      change {GolfScoring.Competition.EventLifecycleGuard, operation: :mark_event_live}
    end

    update :complete_event do
      public? false
      accept []
      transaction? true
      require_atomic? false
      atomic_upgrade? false
      change {GolfScoring.Competition.EventLifecycleGuard, operation: :complete_event}
    end

    update :archive_event do
      public? false
      accept []
      transaction? true
      require_atomic? false
      atomic_upgrade? false
      change {GolfScoring.Competition.EventLifecycleGuard, operation: :archive_event}
    end

    update :cancel_event do
      public? false
      accept []
      transaction? true
      require_atomic? false
      atomic_upgrade? false
      change {GolfScoring.Competition.EventLifecycleGuard, operation: :cancel_event}
    end
  end

  policies do
    for action <- [
          :publish_event,
          :mark_event_live,
          :complete_event,
          :archive_event,
          :cancel_event
        ] do
      policy action(action) do
        access_type :strict
        authorize_if {GolfScoring.Accounts.Checks.ActiveEventRole, role: :event_admin}
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :state, :atom do
      allow_nil? false
      default :draft
      public? false
      writable? false
      constraints one_of: [:draft, :published, :live, :completed, :archived, :cancelled]
    end

    timestamps()
  end
end
