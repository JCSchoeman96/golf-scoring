defmodule GolfScoring.GolfCatalog.Course do
  @moduledoc "Canonical reusable golf course identity."

  use Ash.Resource,
    domain: GolfScoring.GolfCatalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "courses"
    repo GolfScoring.Repo

    check_constraints do
      check_constraint :status, "courses_status_must_be_valid",
        check: "status IN ('active', 'archived')",
        message: "must be active or archived"

      check_constraint :name, "courses_name_must_be_present",
        check: "char_length(btrim(name)) > 0",
        message: "must be present"
    end
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :create_course do
      public? false
      accept [:name, :location]
      change set_attribute(:status, :active)

      argument :event_id, :uuid do
        allow_nil? false
      end

      validate present([:name, :location])
    end

    update :update_course do
      public? false
      accept [:name, :location]
      require_atomic? false
      atomic_upgrade? false
      change {GolfScoring.GolfCatalog.CourseCatalogGuard, operation: :update_course}

      argument :event_id, :uuid do
        allow_nil? false
      end

      validate present([:name, :location])
    end

    update :archive_course do
      public? false
      accept []
      require_atomic? false
      atomic_upgrade? false
      change {GolfScoring.GolfCatalog.CourseCatalogGuard, operation: :archive_course}

      argument :event_id, :uuid do
        allow_nil? false
      end
    end
  end

  policies do
    for action <- [:create_course, :update_course, :archive_course] do
      policy action(action) do
        access_type :strict
        authorize_if {GolfScoring.Accounts.Checks.ActiveEventRole, role: :event_admin}
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :location, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :active
      public? false
      writable? false
      constraints one_of: [:active, :archived]
    end

    timestamps()
  end

  relationships do
    has_many :course_holes, GolfScoring.GolfCatalog.CourseHole
  end
end
