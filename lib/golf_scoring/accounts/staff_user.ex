defmodule GolfScoring.Accounts.StaffUser do
  @moduledoc "Authentication identity and system capability for staff members."

  use Ash.Resource,
    domain: GolfScoring.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  postgres do
    table "staff_users"
    repo GolfScoring.Repo

    check_constraints do
      check_constraint :status, "staff_users_status_must_be_valid",
        check: "status IN ('active', 'suspended', 'disabled')",
        message: "must be active, suspended, or disabled"
    end
  end

  authentication do
    # The generic sign-in form slugifies multiword subjects before submitting them.
    subject_name(:staffuser)

    tokens do
      enabled?(false)
      token_resource(false)
    end

    strategies do
      password :password do
        identity_field(:email)
        hashed_password_field(:hashed_password)
        registration_enabled?(false)
        sign_in_tokens_enabled?(false)
      end
    end
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    read :get_by_subject do
      public? false
      argument :subject, :string, allow_nil?: false
      prepare build(filter: [status: :active])
      prepare AshAuthentication.Preparations.FilterBySubject
      get? true
    end

    update :grant_system_admin do
      public? false
      accept []
      transaction? true
      require_atomic? false
      atomic_upgrade? false
      change {GolfScoring.Accounts.SystemAdminGuard, operation: :grant}
    end

    update :revoke_system_admin do
      public? false
      accept []
      transaction? true
      require_atomic? false
      atomic_upgrade? false
      change {GolfScoring.Accounts.SystemAdminGuard, operation: :revoke}
    end

    create :provision_staff_user do
      public? false
      accept [:email]
      change set_attribute(:status, :active)

      argument :password, :string do
        allow_nil? false
        sensitive? true
        constraints min_length: 15
      end

      argument :password_confirmation, :string do
        allow_nil? false
        sensitive? true
        constraints min_length: 15
      end

      validate {AshAuthentication.Strategy.Password.PasswordConfirmationValidation,
                strategy_name: :password}

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    read :sign_in_with_password do
      public? true

      argument :email, :ci_string do
        allow_nil? false
      end

      argument :password, :string do
        allow_nil? false
        sensitive? true
      end

      prepare build(filter: [status: :active])
      prepare AshAuthentication.Strategy.Password.SignInPreparation

      get? true
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action(:grant_system_admin) do
      access_type :strict
      forbid_unless actor_attribute_equals(:status, :active)
      authorize_if actor_attribute_equals(:system_admin, true)
    end

    policy action(:revoke_system_admin) do
      access_type :strict
      forbid_unless actor_attribute_equals(:status, :active)
      authorize_if actor_attribute_equals(:system_admin, true)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:active, :suspended, :disabled]
    end

    attribute :system_admin, :boolean do
      allow_nil? false
      default false
      public? false
      writable? false
    end

    attribute :hashed_password, :string do
      allow_nil? false
      public? false
      sensitive? true
      select_by_default? false
    end

    timestamps()
  end

  identities do
    identity :unique_email, [:email]
  end
end
