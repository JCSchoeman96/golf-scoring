defmodule GolfScoring.Competition.CompetitionSideResult do
  @moduledoc "Official competitive readiness state for one CompetitionSide."

  use Ash.Resource,
    domain: GolfScoring.Competition,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "competition_side_results"
    repo GolfScoring.Repo

    references do
      reference :competition_side, on_delete: :restrict
    end

    custom_indexes do
      index [:competition_side_id]
    end

    check_constraints do
      check_constraint :state, "competition_side_results_state_must_be_valid",
        check:
          "state IN ('provisional', 'review_required', 'ready_to_finalize', 'finalized', 'excluded')",
        message: "must be a valid CompetitionSideResult lifecycle state"
    end

    identity_index_names unique_result_per_side: "competition_side_results_unique_side_index"
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :create_provisional_internal do
      public? false
      accept [:competition_side_id]
      change set_attribute(:state, :provisional)
    end

    update :mark_review_required do
      public? false
      accept []
      require_atomic? false
      atomic_upgrade? false

      change {GolfScoring.Competition.CompetitionSideResultLifecycleGuard,
              operation: :mark_review_required}
    end

    update :mark_ready_to_finalize do
      public? false
      accept []
      require_atomic? false
      atomic_upgrade? false

      change {GolfScoring.Competition.CompetitionSideResultLifecycleGuard,
              operation: :mark_ready_to_finalize}
    end

    update :finalize do
      public? false
      accept []
      require_atomic? false
      atomic_upgrade? false
      change {GolfScoring.Competition.CompetitionSideResultLifecycleGuard, operation: :finalize}
    end

    update :reopen do
      public? false
      accept []
      require_atomic? false
      atomic_upgrade? false
      change {GolfScoring.Competition.CompetitionSideResultLifecycleGuard, operation: :reopen}
    end

    update :exclude do
      public? false
      accept []
      require_atomic? false
      atomic_upgrade? false
      change {GolfScoring.Competition.CompetitionSideResultLifecycleGuard, operation: :exclude}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :state, :atom do
      allow_nil? false
      default :provisional
      public? false
      writable? false

      constraints one_of: [
                    :provisional,
                    :review_required,
                    :ready_to_finalize,
                    :finalized,
                    :excluded
                  ]
    end

    timestamps()
  end

  relationships do
    belongs_to :competition_side, GolfScoring.Competition.CompetitionSide do
      allow_nil? false
      public? false
    end
  end

  identities do
    identity :unique_result_per_side, [:competition_side_id]
  end
end
