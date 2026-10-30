defmodule GolfScoring.GolfCatalog.TeeRatingProfile do
  @moduledoc "Handicap/scoring rating context for one physical TeeSet."

  use Ash.Resource,
    domain: GolfScoring.GolfCatalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "tee_rating_profiles"
    repo GolfScoring.Repo

    references do
      reference :tee_set, on_delete: :restrict
    end

    check_constraints do
      check_constraint :rating_label, "tee_rating_profiles_rating_label_must_be_present",
        check: "char_length(btrim(rating_label)) > 0",
        message: "must be present"
    end
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :configure_tee_rating_profile do
      public? false

      accept [
        :tee_set_id,
        :rating_label,
        :course_rating,
        :slope_rating,
        :total_par,
        :hole_ratings
      ]

      upsert? true
      upsert_identity :unique_rating_context_per_tee_set
      upsert_fields [:course_rating, :slope_rating, :total_par, :hole_ratings]

      argument :event_id, :uuid do
        allow_nil? false
      end

      validate present([:tee_set_id, :rating_label, :course_rating, :slope_rating, :total_par])

      change GolfScoring.GolfCatalog.Changes.ValidateTeeRatingProfileHoleRatings
    end
  end

  policies do
    policy action(:configure_tee_rating_profile) do
      access_type :strict
      authorize_if {GolfScoring.Accounts.Checks.ActiveEventRole, role: :event_admin}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :rating_label, :string do
      allow_nil? false
      public? true
    end

    attribute :course_rating, :decimal do
      allow_nil? false
      public? true
      constraints precision: 4, scale: 1
    end

    attribute :slope_rating, :integer do
      allow_nil? false
      public? true
      constraints min: 55, max: 155
    end

    attribute :total_par, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :hole_ratings, {:array, GolfScoring.GolfCatalog.TeeRatingProfile.HoleRating} do
      allow_nil? false
      public? true
      default []
    end

    timestamps()
  end

  relationships do
    belongs_to :tee_set, GolfScoring.GolfCatalog.TeeSet do
      allow_nil? false
      public? false
    end
  end

  identities do
    identity :unique_rating_context_per_tee_set, [:tee_set_id, :rating_label]
  end
end
