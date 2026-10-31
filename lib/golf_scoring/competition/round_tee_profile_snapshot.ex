defmodule GolfScoring.Competition.RoundTeeProfileSnapshot do
  @moduledoc "Immutable Round copy of one TeeRatingProfile's scoring facts."

  use Ash.Resource,
    domain: GolfScoring.Competition,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "round_tee_profile_snapshots"
    repo GolfScoring.Repo

    identity_index_names unique_source_profile_per_round:
                           "round_tee_profile_snapshots_source_profile_idx"

    references do
      reference :round, on_delete: :restrict, match_with: [course_id: :course_id]
      reference :course, on_delete: :restrict
      reference :source_tee_set, on_delete: :restrict, match_with: [course_id: :course_id]

      reference :source_tee_rating_profile,
        on_delete: :restrict,
        match_with: [source_tee_set_id: :tee_set_id]
    end

    check_constraints do
      check_constraint :slope_rating, "round_tee_profile_snapshots_slope_rating_in_range",
        check: "slope_rating >= 55 AND slope_rating <= 155",
        message: "must be between 55 and 155"

      check_constraint :total_par, "round_tee_profile_snapshots_total_par_positive",
        check: "total_par > 0",
        message: "must be positive"

      check_constraint :applicable_par, "round_tee_profile_snapshots_applicable_par_positive",
        check: "applicable_par > 0",
        message: "must be positive"
    end
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :insert_snapshot do
      public? false

      accept [
        :round_id,
        :course_id,
        :source_tee_set_id,
        :source_tee_rating_profile_id,
        :tee_set_name,
        :rating_label,
        :course_rating,
        :slope_rating,
        :total_par,
        :applicable_par,
        :source_tee_set_updated_at,
        :source_tee_rating_profile_updated_at
      ]
    end

    update :refresh_snapshot_values do
      public? false

      accept [
        :tee_set_name,
        :rating_label,
        :course_rating,
        :slope_rating,
        :total_par,
        :applicable_par,
        :source_tee_set_updated_at,
        :source_tee_rating_profile_updated_at
      ]

      require_atomic? false
    end

    destroy :remove_snapshot do
      public? false
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :tee_set_name, :string do
      allow_nil? false
      public? false
    end

    attribute :rating_label, :string do
      allow_nil? false
      public? false
    end

    attribute :course_rating, :decimal do
      allow_nil? false
      public? false
      constraints precision: 4, scale: 1
    end

    attribute :slope_rating, :integer do
      allow_nil? false
      public? false
      constraints min: 55, max: 155
    end

    attribute :total_par, :integer do
      allow_nil? false
      public? false
      constraints min: 1
    end

    attribute :applicable_par, :integer do
      allow_nil? false
      public? false
      constraints min: 1
    end

    attribute :source_tee_set_updated_at, :utc_datetime_usec do
      allow_nil? false
      public? false
    end

    attribute :source_tee_rating_profile_updated_at, :utc_datetime_usec do
      allow_nil? false
      public? false
    end

    timestamps()
  end

  relationships do
    belongs_to :round, GolfScoring.Competition.Round do
      allow_nil? false
      public? false
    end

    belongs_to :course, GolfScoring.GolfCatalog.Course do
      allow_nil? false
      public? false
    end

    belongs_to :source_tee_set, GolfScoring.GolfCatalog.TeeSet do
      allow_nil? false
      public? false
    end

    belongs_to :source_tee_rating_profile, GolfScoring.GolfCatalog.TeeRatingProfile do
      allow_nil? false
      public? false
    end

    has_many :round_tee_hole_snapshots, GolfScoring.Competition.RoundTeeHoleSnapshot
  end

  identities do
    identity :unique_id_per_round, [:id, :round_id]
    identity :unique_source_profile_per_round, [:round_id, :source_tee_rating_profile_id]
  end
end
