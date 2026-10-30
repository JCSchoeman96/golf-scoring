defmodule GolfScoring.GolfCatalog.CourseHole do
  @moduledoc "A physical hole identity on a Course."

  use Ash.Resource,
    domain: GolfScoring.GolfCatalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "course_holes"
    repo GolfScoring.Repo

    references do
      reference :course, on_delete: :restrict
    end

    check_constraints do
      check_constraint :hole_number, "course_holes_hole_number_must_be_positive",
        check: "hole_number > 0",
        message: "must be a positive physical hole number"
    end
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :configure_course_hole do
      public? false
      accept [:course_id, :hole_number]
      upsert? true
      upsert_identity :unique_hole_per_course
      upsert_fields []

      argument :event_id, :uuid do
        allow_nil? false
      end

      validate compare(:hole_number, greater_than: 0)
    end
  end

  policies do
    policy action(:configure_course_hole) do
      access_type :strict
      authorize_if {GolfScoring.Accounts.Checks.ActiveEventRole, role: :event_admin}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :hole_number, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    timestamps()
  end

  relationships do
    belongs_to :course, GolfScoring.GolfCatalog.Course do
      allow_nil? false
      public? false
    end
  end

  identities do
    identity :unique_hole_per_course, [:course_id, :hole_number]
  end
end
