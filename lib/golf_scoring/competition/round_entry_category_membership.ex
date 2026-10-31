defmodule GolfScoring.Competition.RoundEntryCategoryMembership do
  @moduledoc "Joins one RoundEntry to one CompetitionCategory within the same Round."

  use Ash.Resource,
    domain: GolfScoring.Competition,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "round_entry_category_memberships"
    repo GolfScoring.Repo

    references do
      reference :round, on_delete: :restrict
      reference :round_entry, on_delete: :restrict, match_with: [round_id: :round_id]

      reference :competition_category,
        on_delete: :restrict,
        match_with: [round_id: :round_id]
    end

    custom_indexes do
      index [:round_entry_id]
      index [:competition_category_id]
      index [:round_id]
    end

    identity_index_names unique_membership_per_entry_category:
                           "round_entry_category_memberships_unique_index"
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :create_internal do
      public? false

      accept [:round_id, :round_entry_id, :competition_category_id]
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
    belongs_to :round, GolfScoring.Competition.Round do
      allow_nil? false
      public? false
    end

    belongs_to :round_entry, GolfScoring.Competition.RoundEntry do
      allow_nil? false
      public? false
    end

    belongs_to :competition_category, GolfScoring.Competition.CompetitionCategory do
      allow_nil? false
      public? false
    end
  end

  identities do
    identity :unique_membership_per_entry_category, [:round_entry_id, :competition_category_id]
  end
end
