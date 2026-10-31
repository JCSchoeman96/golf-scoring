defmodule GolfScoring.Competition.CompetitionSideMembership do
  @moduledoc "Joins one RoundEntry to one CompetitionSide within a RoundCompetition."

  use Ash.Resource,
    domain: GolfScoring.Competition,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "competition_side_memberships"
    repo GolfScoring.Repo

    references do
      reference :round, on_delete: :restrict

      reference :round_competition,
        on_delete: :restrict,
        match_with: [round_id: :round_id]

      reference :competition_side,
        on_delete: :restrict,
        match_with: [round_competition_id: :round_competition_id, round_id: :round_id]

      reference :round_entry,
        on_delete: :restrict,
        match_with: [round_id: :round_id]
    end

    custom_indexes do
      index [:round_competition_id]
      index [:competition_side_id]
      index [:round_entry_id]
      index [:round_id]
    end

    identity_index_names unique_entry_per_competition:
                           "competition_side_memberships_unique_entry_per_competition_index"
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :create_internal do
      public? false

      accept [:round_competition_id, :competition_side_id, :round_entry_id, :round_id]
    end

    destroy :destroy_internal do
      public? false
    end
  end

  attributes do
    uuid_primary_key :id

    timestamps()
  end

  relationships do
    belongs_to :round_competition, GolfScoring.Competition.RoundCompetition do
      allow_nil? false
      public? false
    end

    belongs_to :competition_side, GolfScoring.Competition.CompetitionSide do
      allow_nil? false
      public? false
    end

    belongs_to :round_entry, GolfScoring.Competition.RoundEntry do
      allow_nil? false
      public? false
    end

    belongs_to :round, GolfScoring.Competition.Round do
      allow_nil? false
      public? false
    end
  end

  identities do
    identity :unique_entry_per_competition, [:round_competition_id, :round_entry_id]
  end
end
