defmodule GolfScoring.GolfCatalog.TeeSet do
  @moduledoc "Physical tee marker identity on a Course."

  use Ash.Resource,
    domain: GolfScoring.GolfCatalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "tee_sets"
    repo GolfScoring.Repo

    references do
      reference :course, on_delete: :restrict
    end

    check_constraints do
      check_constraint :name, "tee_sets_name_must_be_present",
        check: "char_length(btrim(name)) > 0",
        message: "must be present"
    end
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :configure_tee_set do
      public? false
      accept [:course_id, :name]
      upsert? true
      upsert_identity :unique_tee_marker_per_course
      upsert_fields [:name]

      argument :event_id, :uuid do
        allow_nil? false
      end

      validate present([:course_id, :name])

      validate {GolfScoring.GolfCatalog.Validations.ReferencedCourseActiveInDatabase,
                before_action?: true}
    end
  end

  policies do
    policy action(:configure_tee_set) do
      access_type :strict
      authorize_if {GolfScoring.Accounts.Checks.ActiveEventRole, role: :event_admin}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :course, GolfScoring.GolfCatalog.Course do
      allow_nil? false
      public? false
    end

    has_many :tee_rating_profiles, GolfScoring.GolfCatalog.TeeRatingProfile
  end

  identities do
    identity :unique_tee_marker_per_course, [:course_id, :name]
  end
end
