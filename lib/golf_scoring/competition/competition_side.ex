defmodule GolfScoring.Competition.CompetitionSide do
  @moduledoc "One competitive side within a RoundCompetition."

  use Ash.Resource,
    domain: GolfScoring.Competition,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "competition_sides"
    repo GolfScoring.Repo

    references do
      reference :round, on_delete: :restrict

      reference :round_competition,
        on_delete: :restrict,
        match_with: [round_id: :round_id]
    end

    custom_indexes do
      index [:round_competition_id]
      index [:round_id]
    end

    check_constraints do
      check_constraint :formation, "competition_sides_formation_must_be_valid",
        check: "formation IN ('partnership', 'solo')",
        message: "must be partnership or solo"
    end
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :create_competition_side_internal do
      public? false
      accept [:round_competition_id, :round_id, :formation]
      transaction? true
      change GolfScoring.Competition.Changes.CreateCompetitionSide
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :formation, :atom do
      allow_nil? false
      public? false
      constraints one_of: [:partnership, :solo]
    end

    timestamps()
  end

  relationships do
    belongs_to :round_competition, GolfScoring.Competition.RoundCompetition do
      allow_nil? false
      public? false
    end

    belongs_to :round, GolfScoring.Competition.Round do
      allow_nil? false
      public? false
    end

    has_one :result, GolfScoring.Competition.CompetitionSideResult
    has_many :memberships, GolfScoring.Competition.CompetitionSideMembership
  end

  identities do
    identity :unique_id_per_round_competition, [:id, :round_id, :round_competition_id]
  end
end
