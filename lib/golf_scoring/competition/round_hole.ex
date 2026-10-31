defmodule GolfScoring.Competition.RoundHole do
  @moduledoc "Structural hole identity within a Round route."

  use Ash.Resource,
    domain: GolfScoring.Competition,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "round_holes"
    repo GolfScoring.Repo

    references do
      reference :round, on_delete: :restrict, match_with: [course_id: :course_id]
      reference :course_hole, on_delete: :restrict, match_with: [course_id: :course_id]
    end

    check_constraints do
      check_constraint :play_order, "round_holes_play_order_must_be_positive",
        check: "play_order > 0",
        message: "must be a positive play order"

      check_constraint :display_hole_number, "round_holes_display_hole_number_must_be_positive",
        check: "display_hole_number > 0",
        message: "must be a positive display hole number"
    end
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :insert_layout_row do
      public? false
      accept [:round_id, :course_hole_id, :course_id, :play_order, :display_hole_number]
    end

    update :update_layout_row do
      public? false
      accept [:play_order, :display_hole_number]
      require_atomic? false
    end

    destroy :remove_layout_row do
      public? false
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :play_order, :integer do
      allow_nil? false
      public? false
      constraints min: 1
    end

    attribute :display_hole_number, :integer do
      allow_nil? false
      public? false
      constraints min: 1
    end

    timestamps()
  end

  relationships do
    belongs_to :round, GolfScoring.Competition.Round do
      allow_nil? false
      public? false
    end

    belongs_to :course_hole, GolfScoring.GolfCatalog.CourseHole do
      allow_nil? false
      public? false
    end

    belongs_to :course, GolfScoring.GolfCatalog.Course do
      allow_nil? false
      public? false
    end
  end

  identities do
    identity :unique_play_order_per_round, [:round_id, :play_order]
    identity :unique_course_hole_per_round, [:round_id, :course_hole_id]
  end
end
