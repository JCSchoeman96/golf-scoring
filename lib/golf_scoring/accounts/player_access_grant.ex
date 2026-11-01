defmodule GolfScoring.Accounts.PlayerAccessGrant do
  @moduledoc "Event-scoped player access credential; digest-only durable token material."

  use Ash.Resource,
    domain: GolfScoring.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "player_access_grants"
    repo GolfScoring.Repo

    references do
      reference :event, on_delete: :restrict
      reference :player, on_delete: :restrict
    end

    check_constraints do
      check_constraint :state, "player_access_grants_state_must_be_valid",
        check: "state IN ('active', 'superseded', 'revoked', 'expired')",
        message: "must be active, superseded, revoked, or expired"
    end

    custom_indexes do
      index [:event_id, :player_id]
    end

    identity_index_names unique_token_digest: "player_access_grants_token_digest_index",
                         unique_active_event_player:
                           "player_access_grants_one_active_event_player_index"

    identity_wheres_to_sql unique_active_event_player: "state = 'active'"
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :create_internal do
      public? false

      accept [:event_id, :player_id, :token_digest, :state, :expires_at]

      validate present([:event_id, :player_id, :token_digest])
      validate one_of(:state, [:active])
    end

    update :mark_superseded_internal do
      public? false
      accept []
      require_atomic? false

      validate attribute_equals(:state, :active)
      change set_attribute(:state, :superseded)
    end

    update :mark_revoked_internal do
      public? false
      accept []
      require_atomic? false

      validate attribute_equals(:state, :active)
      change set_attribute(:state, :revoked)
    end

    update :mark_expired_internal do
      public? false
      accept []
      require_atomic? false

      validate attribute_equals(:state, :active)
      change set_attribute(:state, :expired)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :token_digest, :binary do
      allow_nil? false
      public? false
      sensitive? true
    end

    attribute :state, :atom do
      allow_nil? false
      public? false
      default :active
      constraints one_of: [:active, :superseded, :revoked, :expired]
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? true
      public? false
    end

    timestamps()
  end

  relationships do
    belongs_to :event, GolfScoring.Competition.Event do
      allow_nil? false
      public? false
    end

    belongs_to :player, GolfScoring.Competition.Player do
      allow_nil? false
      public? false
    end
  end

  identities do
    identity :unique_token_digest, [:token_digest]

    identity :unique_active_event_player, [:event_id, :player_id], where: expr(state == :active)
  end
end
