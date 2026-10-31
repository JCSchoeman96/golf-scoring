defmodule GolfScoring.Competition.RoundCompetition do
  @moduledoc "Concrete competition configuration for one Round."

  use Ash.Resource,
    domain: GolfScoring.Competition,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "round_competitions"
    repo GolfScoring.Repo

    references do
      reference :event, on_delete: :restrict
      reference :round, on_delete: :restrict, match_with: [event_id: :event_id]
    end

    custom_indexes do
      index [:round_id]
      index [:event_id]

      index [:round_id],
        unique: true,
        name: "round_competitions_one_primary_per_round_index",
        where: "is_primary = true"
    end

    check_constraints do
      check_constraint :scoring_policy_identifier,
                       "round_competitions_scoring_policy_must_be_present",
                       check: "btrim(scoring_policy_identifier) <> ''",
                       message: "must be present"
    end

    identity_index_names unique_primary_per_round:
                           "round_competitions_one_primary_per_round_index"

    identity_wheres_to_sql unique_primary_per_round: "is_primary = true"
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :configure_internal do
      public? false

      accept [
        :event_id,
        :round_id,
        :is_primary,
        :scoring_policy_identifier,
        :handicap_allowance_percent,
        :solo_sides_permitted,
        :solo_normalization_policy_identifier,
        :pickup_policy_identifier,
        :competition_terms_reference
      ]
    end

    update :update_configuration_internal do
      public? false

      accept [
        :solo_sides_permitted,
        :handicap_allowance_percent,
        :solo_normalization_policy_identifier,
        :pickup_policy_identifier,
        :competition_terms_reference
      ]

      require_atomic? false
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :is_primary, :boolean do
      allow_nil? false
      default true
      public? false
    end

    attribute :scoring_policy_identifier, :string do
      allow_nil? false
      default "four_ball_stableford_v1"
      public? false
      constraints trim?: true, min_length: 1
    end

    attribute :handicap_allowance_percent, :integer do
      allow_nil? false
      default 100
      public? false
      constraints min: 0, max: 100
    end

    attribute :solo_sides_permitted, :boolean do
      allow_nil? false
      default false
      public? false
    end

    attribute :solo_normalization_policy_identifier, :string do
      allow_nil? false
      default "companion_max_p_minus_one_v1"
      public? false
      constraints trim?: true, min_length: 1
    end

    attribute :pickup_policy_identifier, :string do
      allow_nil? false
      default "standard_pickup_v1"
      public? false
      constraints trim?: true, min_length: 1
    end

    attribute :competition_terms_reference, :string do
      allow_nil? true
      public? false
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

    has_many :competition_sides, GolfScoring.Competition.CompetitionSide
  end

  identities do
    identity :unique_primary_per_round, [:round_id], where: expr(is_primary == true)
    identity :unique_id_per_round, [:id, :round_id]
  end
end
