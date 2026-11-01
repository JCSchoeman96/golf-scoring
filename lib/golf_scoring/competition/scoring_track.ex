defmodule GolfScoring.Competition.ScoringTrack do
  @moduledoc "One derived leaderboard/scoring view for a RoundCompetition."

  use Ash.Resource,
    domain: GolfScoring.Competition,
    data_layer: AshPostgres.DataLayer

  @track_types [:mystery, :standard_better_ball]
  @configuration_states [:draft, :locked]

  postgres do
    table "scoring_tracks"
    repo GolfScoring.Repo

    references do
      reference :event, on_delete: :restrict

      reference :round,
        on_delete: :restrict,
        match_with: [event_id: :event_id]

      reference :round_competition,
        on_delete: :restrict,
        match_with: [round_id: :round_id]
    end

    custom_indexes do
      index [:round_competition_id]
      index [:round_id]
      index [:event_id]
    end

    check_constraints do
      check_constraint :track_type, "scoring_tracks_track_type_must_be_valid",
        check: "track_type IN ('mystery', 'standard_better_ball')",
        message: "must be mystery or standard_better_ball"

      check_constraint :name, "scoring_tracks_name_must_be_present",
        check: "btrim(name) <> ''",
        message: "must be present"

      check_constraint :visibility_policy_identifier,
                       "scoring_tracks_visibility_policy_must_be_present",
                       check: "btrim(visibility_policy_identifier) <> ''",
                       message: "must be present"

      check_constraint :aggregation_policy_identifier,
                       "scoring_tracks_aggregation_policy_must_be_present",
                       check: "btrim(aggregation_policy_identifier) <> ''",
                       message: "must be present"

      check_constraint :tie_break_policy_identifier,
                       "scoring_tracks_tie_break_policy_must_be_present",
                       check: "btrim(tie_break_policy_identifier) <> ''",
                       message: "must be present"

      check_constraint :configuration_state, "scoring_tracks_configuration_state_must_be_valid",
        check: "configuration_state IN ('draft', 'locked')",
        message: "must be draft or locked"
    end

    identity_index_names unique_primary_per_round_competition:
                           "scoring_tracks_one_primary_per_round_competition_index"

    identity_wheres_to_sql unique_primary_per_round_competition: "is_primary = true"
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :configure_scoring_track_internal do
      public? false

      accept [
        :event_id,
        :round_id,
        :round_competition_id,
        :track_type,
        :name,
        :is_primary,
        :visibility_policy_identifier,
        :aggregation_policy_identifier,
        :tie_break_policy_identifier,
        :configuration_state
      ]
    end

    update :update_scoring_track_configuration_internal do
      public? false

      accept [
        :name,
        :is_primary,
        :visibility_policy_identifier,
        :aggregation_policy_identifier,
        :tie_break_policy_identifier
      ]

      require_atomic? false
    end

    update :lock_configuration_internal do
      public? false
      accept []
      require_atomic? false

      change set_attribute(:configuration_state, :locked)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :track_type, :atom do
      allow_nil? false
      public? false
      constraints one_of: @track_types
    end

    attribute :name, :string do
      allow_nil? false
      public? false
      constraints trim?: true, min_length: 1
    end

    attribute :is_primary, :boolean do
      allow_nil? false
      default false
      public? false
    end

    attribute :visibility_policy_identifier, :string do
      allow_nil? false
      public? false
      constraints trim?: true, min_length: 1
    end

    attribute :aggregation_policy_identifier, :string do
      allow_nil? false
      public? false
      constraints trim?: true, min_length: 1
    end

    attribute :tie_break_policy_identifier, :string do
      allow_nil? false
      public? false
      constraints trim?: true, min_length: 1
    end

    attribute :configuration_state, :atom do
      allow_nil? false
      default :draft
      public? false
      constraints one_of: @configuration_states
    end

    timestamps()
  end

  relationships do
    belongs_to :event, GolfScoring.Competition.Event do
      allow_nil? false
      public? false
    end

    belongs_to :round, GolfScoring.Competition.Round do
      allow_nil? false
      public? false
    end

    belongs_to :round_competition, GolfScoring.Competition.RoundCompetition do
      allow_nil? false
      public? false
    end

    has_many :mystery_hole_rules, GolfScoring.Competition.MysteryHoleRule
  end

  identities do
    identity :unique_primary_per_round_competition, [:round_competition_id],
      where: expr(is_primary == true)

    identity :unique_id_per_round, [:id, :round_id]
    identity :unique_id_per_round_competition, [:id, :round_id, :round_competition_id]
  end
end
