defmodule GolfScoring.Competition.Player do
  @moduledoc "Reusable golfer identity outside any single Round."

  use Ash.Resource,
    domain: GolfScoring.Competition,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "players"
    repo GolfScoring.Repo
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :create_internal do
      public? false

      accept [
        :first_name,
        :surname,
        :email,
        :mobile_number,
        :latest_handicap_index
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :first_name, :string do
      allow_nil? false
      public? false
      constraints min_length: 1
    end

    attribute :surname, :string do
      allow_nil? false
      public? false
      constraints min_length: 1
    end

    attribute :email, :string do
      allow_nil? true
      public? false
    end

    attribute :mobile_number, :string do
      allow_nil? true
      public? false
    end

    attribute :latest_handicap_index, :decimal do
      allow_nil? true
      public? false
    end

    timestamps()
  end

  relationships do
    has_many :round_entries, GolfScoring.Competition.RoundEntry
  end
end
