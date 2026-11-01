defmodule GolfScoring.Competition.MysteryHoleRule do
  @moduledoc "Secret Mystery aggregation rule for one ScoringTrack and RoundHole."

  use Ash.Resource,
    domain: GolfScoring.Competition,
    data_layer: AshPostgres.DataLayer

  @rule_values [:best, :worst, :both]

  postgres do
    table "mystery_hole_rules"
    repo GolfScoring.Repo

    references do
      reference :round, on_delete: :restrict

      reference :scoring_track,
        on_delete: :restrict,
        match_with: [round_id: :round_id]

      reference :round_hole,
        on_delete: :restrict,
        match_with: [round_id: :round_id]
    end

    custom_indexes do
      index [:scoring_track_id]
      index [:round_hole_id]
      index [:round_id]
    end

    check_constraints do
      check_constraint :rule, "mystery_hole_rules_rule_must_be_valid",
        check: "rule IN ('best', 'worst', 'both')",
        message: "must be best, worst, or both"
    end

    identity_index_names unique_track_hole: "mystery_hole_rules_unique_track_hole_index"
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :configure_mystery_hole_rule_internal do
      public? false
      accept [:scoring_track_id, :round_hole_id, :round_id, :rule]
    end

    update :update_mystery_hole_rule_internal do
      public? false
      accept [:rule]
      require_atomic? false
    end

    destroy :remove_mystery_hole_rule_internal do
      public? false
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :rule, :atom do
      allow_nil? false
      public? false
      sensitive? true
      constraints one_of: @rule_values
    end

    timestamps()
  end

  relationships do
    belongs_to :scoring_track, GolfScoring.Competition.ScoringTrack do
      allow_nil? false
      public? false
    end

    belongs_to :round_hole, GolfScoring.Competition.RoundHole do
      allow_nil? false
      public? false
    end

    belongs_to :round, GolfScoring.Competition.Round do
      allow_nil? false
      public? false
    end
  end

  identities do
    identity :unique_track_hole, [:scoring_track_id, :round_hole_id]

    identity :unique_id_per_round, [:id, :round_id, :scoring_track_id, :round_hole_id]
  end
end
