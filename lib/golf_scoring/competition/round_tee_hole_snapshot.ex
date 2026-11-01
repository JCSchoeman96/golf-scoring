defmodule GolfScoring.Competition.RoundTeeHoleSnapshot do
  @moduledoc "Per-hole scoring facts for one RoundTeeProfileSnapshot."

  use Ash.Resource,
    domain: GolfScoring.Competition,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "round_tee_hole_snapshots"
    repo GolfScoring.Repo

    references do
      reference :round_tee_profile_snapshot,
        on_delete: :restrict,
        match_with: [round_id: :round_id]

      reference :round, on_delete: :restrict
      reference :round_hole, on_delete: :restrict, match_with: [round_id: :round_id]
    end

    custom_indexes do
      index [:round_tee_profile_snapshot_id, :plus_stroke_order],
        unique: true,
        name: "round_tee_hole_snapshots_unique_plus_stroke_order_per_profile",
        where: "plus_stroke_order IS NOT NULL"
    end

    check_constraints do
      check_constraint :par, "round_tee_hole_snapshots_par_in_range",
        check: "par >= 3 AND par <= 7",
        message: "must be between 3 and 7"

      check_constraint :stroke_index, "round_tee_hole_snapshots_stroke_index_positive",
        check: "stroke_index > 0",
        message: "must be positive"

      check_constraint :distance_m, "round_tee_hole_snapshots_distance_positive",
        check: "distance_m IS NULL OR distance_m > 0",
        message: "must be positive when present"

      check_constraint :plus_stroke_order, "round_tee_hole_snapshots_plus_stroke_order_in_range",
        check: "plus_stroke_order IS NULL OR (plus_stroke_order >= 1 AND plus_stroke_order <= 8)",
        message: "must be between 1 and 8 when present"
    end
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :insert_hole_snapshot do
      public? false

      accept [
        :round_tee_profile_snapshot_id,
        :round_id,
        :round_hole_id,
        :par,
        :stroke_index,
        :distance_m,
        :plus_stroke_order
      ]
    end

    update :refresh_hole_snapshot_values do
      public? false
      accept [:par, :stroke_index, :distance_m, :plus_stroke_order]
      require_atomic? false
    end

    destroy :remove_hole_snapshot do
      public? false
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :par, :integer do
      allow_nil? false
      public? false
      constraints min: 3, max: 7
    end

    attribute :stroke_index, :integer do
      allow_nil? false
      public? false
      constraints min: 1
    end

    attribute :distance_m, :integer do
      allow_nil? true
      public? false
      constraints min: 1
    end

    attribute :plus_stroke_order, :integer do
      allow_nil? true
      public? false
      constraints min: 1, max: 8
    end

    timestamps()
  end

  relationships do
    belongs_to :round_tee_profile_snapshot, GolfScoring.Competition.RoundTeeProfileSnapshot do
      allow_nil? false
      public? false
    end

    belongs_to :round, GolfScoring.Competition.Round do
      allow_nil? false
      public? false
    end

    belongs_to :round_hole, GolfScoring.Competition.RoundHole do
      allow_nil? false
      public? false
    end
  end

  identities do
    identity :unique_hole_per_profile_snapshot, [:round_tee_profile_snapshot_id, :round_hole_id]
  end
end
