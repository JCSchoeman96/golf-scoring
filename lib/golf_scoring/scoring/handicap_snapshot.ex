defmodule GolfScoring.Scoring.HandicapSnapshot do
  @moduledoc "Competition-independent handicap basis for one RoundEntry."

  use Ash.Resource,
    domain: GolfScoring.Scoring,
    data_layer: AshPostgres.DataLayer

  @basis_sources [
    :official_or_preloaded,
    :player_declared,
    :committee_deemed,
    :committee_override
  ]

  postgres do
    table "handicap_snapshots"
    repo GolfScoring.Repo

    references do
      reference :round, on_delete: :restrict

      reference :round_entry,
        on_delete: :restrict,
        match_with: [round_id: :round_id]

      reference :round_tee_profile_snapshot,
        on_delete: :restrict,
        match_with: [round_id: :round_id]

      reference :confirmed_by_staff_user, on_delete: :restrict

      reference :confirmed_by_round_entry,
        on_delete: :restrict
    end

    custom_indexes do
      index [:round_id]
      index [:round_entry_id]
      index [:round_tee_profile_snapshot_id]
    end

    identity_index_names unique_base_per_entry: "handicap_snapshots_unique_base_per_entry_index",
                         unique_id_entry_round: "handicap_snapshots_unique_id_entry_round_index"

    check_constraints do
      check_constraint :basis_source, "handicap_snapshots_basis_source_valid",
        check:
          "basis_source IN ('official_or_preloaded', 'player_declared', 'committee_deemed', 'committee_override')",
        message: "must be a valid basis source"

      check_constraint :basis_source, "handicap_snapshots_official_basis_shape",
        check: """
        (basis_source IN ('official_or_preloaded', 'player_declared')
          AND source_handicap_index IS NOT NULL
          AND deemed_handicap_basis IS NULL)
        OR
        (basis_source IN ('committee_deemed', 'committee_override')
          AND deemed_handicap_basis IS NOT NULL
          AND source_handicap_index IS NULL)
        """,
        message: "basis source and index/deemed fields are inconsistent"

      check_constraint :basis_source, "handicap_snapshots_override_reason_required",
        check:
          "(basis_source <> 'committee_override') OR (override_reason IS NOT NULL AND btrim(override_reason) <> '')",
        message: "override reason is required"

      check_constraint :confirmed_at, "handicap_snapshots_confirmer_shape",
        check: """
        (
          confirmed_at IS NULL
          AND confirmed_by_staff_user_id IS NULL
          AND confirmed_by_round_entry_id IS NULL
        )
        OR (
          confirmed_at IS NOT NULL
          AND (
            (confirmed_by_staff_user_id IS NOT NULL)::int +
            (confirmed_by_round_entry_id IS NOT NULL)::int
          ) = 1
        )
        """,
        message: "confirmation facts must be absent together or complete together"

      check_constraint :basis_source, "handicap_snapshots_committee_deemed_provenance",
        check: """
        (basis_source <> 'committee_deemed')
        OR (source_reference IS NOT NULL AND btrim(source_reference) <> '')
        """,
        message: "committee deemed basis requires provenance reference"

      check_constraint :confirmed_by_round_entry_id,
                       "handicap_snapshots_player_confirmer_equals_entry",
                       check:
                         "(confirmed_by_round_entry_id IS NULL) OR (confirmed_by_round_entry_id = round_entry_id)",
                       message: "player confirmer must be the target round entry"

      check_constraint :course_handicap_unrounded,
                       "handicap_snapshots_course_handicap_build_consistency",
                       check: """
                       (
                         built_at IS NULL
                         AND course_rating IS NULL
                         AND slope_rating IS NULL
                         AND applicable_par IS NULL
                         AND course_handicap_unrounded IS NULL
                         AND course_handicap_rounded IS NULL
                       )
                       OR (
                         built_at IS NOT NULL
                         AND course_rating IS NOT NULL
                         AND slope_rating IS NOT NULL
                         AND applicable_par IS NOT NULL
                         AND course_handicap_unrounded IS NOT NULL
                         AND course_handicap_rounded IS NOT NULL
                       )
                       """,
                       message:
                         "built snapshot must include tee facts and course handicap outputs together"
    end
  end

  actions do
    read :read do
      public? false
      primary? true
    end

    create :create_configured_internal do
      public? false

      accept [
        :round_id,
        :round_entry_id,
        :round_tee_profile_snapshot_id,
        :basis_source,
        :source_handicap_index,
        :deemed_handicap_basis,
        :confirmed_by_staff_user_id,
        :confirmed_by_round_entry_id,
        :confirmed_at,
        :source_reference,
        :override_reason
      ]
    end

    update :update_basis_internal do
      public? false
      require_atomic? false

      accept [
        :round_tee_profile_snapshot_id,
        :basis_source,
        :source_handicap_index,
        :deemed_handicap_basis,
        :confirmed_by_staff_user_id,
        :confirmed_by_round_entry_id,
        :confirmed_at,
        :source_reference,
        :override_reason,
        :course_rating,
        :slope_rating,
        :applicable_par,
        :course_handicap_unrounded,
        :course_handicap_rounded,
        :built_at
      ]
    end

    update :build_internal do
      public? false
      require_atomic? false

      accept [
        :course_rating,
        :slope_rating,
        :applicable_par,
        :course_handicap_unrounded,
        :course_handicap_rounded,
        :built_at
      ]
    end

    update :realign_round_tee_internal do
      public? false
      require_atomic? false

      accept [:round_tee_profile_snapshot_id]

      change set_attribute(:course_rating, nil)
      change set_attribute(:slope_rating, nil)
      change set_attribute(:applicable_par, nil)
      change set_attribute(:course_handicap_unrounded, nil)
      change set_attribute(:course_handicap_rounded, nil)
      change set_attribute(:built_at, nil)
    end

    update :invalidate_built_internal do
      public? false
      require_atomic? false

      accept [
        :course_rating,
        :slope_rating,
        :applicable_par,
        :course_handicap_unrounded,
        :course_handicap_rounded,
        :built_at
      ]

      change set_attribute(:course_rating, nil)
      change set_attribute(:slope_rating, nil)
      change set_attribute(:applicable_par, nil)
      change set_attribute(:course_handicap_unrounded, nil)
      change set_attribute(:course_handicap_rounded, nil)
      change set_attribute(:built_at, nil)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :basis_source, :atom do
      allow_nil? false
      public? false
      constraints one_of: @basis_sources
    end

    attribute :source_handicap_index, :decimal do
      allow_nil? true
      public? false
    end

    attribute :deemed_handicap_basis, :decimal do
      allow_nil? true
      public? false
    end

    attribute :confirmed_at, :utc_datetime_usec do
      allow_nil? true
      public? false
    end

    attribute :source_reference, :string do
      allow_nil? true
      public? false
    end

    attribute :override_reason, :string do
      allow_nil? true
      public? false
    end

    attribute :course_rating, :decimal do
      allow_nil? true
      public? false
      constraints precision: 4, scale: 1
    end

    attribute :slope_rating, :integer do
      allow_nil? true
      public? false
    end

    attribute :applicable_par, :integer do
      allow_nil? true
      public? false
    end

    attribute :course_handicap_unrounded, :decimal do
      allow_nil? true
      public? false
    end

    attribute :course_handicap_rounded, :integer do
      allow_nil? true
      public? false
    end

    attribute :built_at, :utc_datetime_usec do
      allow_nil? true
      public? false
    end

    timestamps()
  end

  relationships do
    belongs_to :round, GolfScoring.Competition.Round do
      allow_nil? false
      public? false
    end

    belongs_to :round_entry, GolfScoring.Competition.RoundEntry do
      allow_nil? false
      public? false
    end

    belongs_to :round_tee_profile_snapshot, GolfScoring.Competition.RoundTeeProfileSnapshot do
      allow_nil? false
      public? false
    end

    belongs_to :confirmed_by_staff_user, GolfScoring.Accounts.StaffUser do
      allow_nil? true
      public? false
      attribute_public? false
    end

    belongs_to :confirmed_by_round_entry, GolfScoring.Competition.RoundEntry do
      allow_nil? true
      public? false
      attribute_public? false
    end

    has_many :competition_handicaps, GolfScoring.Scoring.CompetitionHandicap
  end

  identities do
    identity :unique_base_per_entry, [:round_entry_id]
    identity :unique_id_per_round, [:id, :round_id]
    identity :unique_id_entry_round, [:id, :round_id, :round_entry_id]
  end

  def basis_sources, do: @basis_sources
end
