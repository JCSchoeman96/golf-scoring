defmodule GolfScoring.Scoring.CompetitionHandicap do
  @moduledoc "Playing handicap for one RoundEntry under one RoundCompetition."

  use Ash.Resource,
    domain: GolfScoring.Scoring,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "competition_handicaps"
    repo GolfScoring.Repo

    references do
      reference :round, on_delete: :restrict

      reference :round_entry,
        on_delete: :restrict,
        match_with: [round_id: :round_id]

      reference :round_competition,
        on_delete: :restrict,
        match_with: [round_id: :round_id]

      reference :handicap_snapshot,
        on_delete: :restrict,
        match_with: [round_id: :round_id, round_entry_id: :round_entry_id]
    end

    custom_indexes do
      index [:round_id]
      index [:round_entry_id]
      index [:round_competition_id]
      index [:handicap_snapshot_id]
    end

    identity_index_names unique_entry_competition:
                           "competition_handicaps_unique_entry_competition_index"

    check_constraints do
      check_constraint :policy_identifier, "competition_handicaps_policy_identifier_present",
        check: "btrim(policy_identifier) <> ''",
        message: "must be present"
    end
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :build_internal do
      public? false

      accept [
        :round_id,
        :round_entry_id,
        :round_competition_id,
        :handicap_snapshot_id,
        :handicap_allowance_percent,
        :allowance_applied,
        :unrounded_allowed_handicap,
        :playing_handicap,
        :policy_identifier
      ]
    end

    destroy :destroy_prestart_internal do
      public? false
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :handicap_allowance_percent, :integer do
      allow_nil? false
      public? false
      constraints min: 0, max: 100
    end

    attribute :allowance_applied, :boolean do
      allow_nil? false
      public? false
    end

    attribute :unrounded_allowed_handicap, :decimal do
      allow_nil? true
      public? false
    end

    attribute :playing_handicap, :integer do
      allow_nil? false
      public? false
    end

    attribute :policy_identifier, :string do
      allow_nil? false
      public? false
      constraints trim?: true, min_length: 1
    end

    timestamps()
  end

  relationships do
    belongs_to :round, GolfScoring.Competition.Round do
      allow_nil? false
      public? false
    end

    belongs_to :round_entry, GolfScoring.Competition.RoundEntry do
      allow_nil? false
      public? false
    end

    belongs_to :round_competition, GolfScoring.Competition.RoundCompetition do
      allow_nil? false
      public? false
    end

    belongs_to :handicap_snapshot, GolfScoring.Scoring.HandicapSnapshot do
      allow_nil? false
      public? false
    end
  end

  identities do
    identity :unique_entry_competition, [:round_entry_id, :round_competition_id]
    identity :unique_id_per_round, [:id, :round_id]
  end
end
