defmodule GolfScoring.Competition.CompetitionCategory do
  @moduledoc "One named competition category configured for a Round."

  use Ash.Resource,
    domain: GolfScoring.Competition,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "competition_categories"
    repo GolfScoring.Repo

    references do
      reference :round, on_delete: :restrict
    end

    custom_indexes do
      index [:round_id]
    end

    check_constraints do
      check_constraint :name, "competition_categories_name_must_be_present",
        check: "btrim(name) <> ''",
        message: "must be present"
    end
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :create_internal do
      public? false
      accept [:round_id, :name]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? false
      constraints min_length: 1, trim?: true
    end

    timestamps()
  end

  relationships do
    belongs_to :round, GolfScoring.Competition.Round do
      allow_nil? false
      public? false
    end

    has_many :round_entry_category_memberships,
             GolfScoring.Competition.RoundEntryCategoryMembership
  end

  identities do
    identity :unique_id_per_round, [:id, :round_id]
  end
end
