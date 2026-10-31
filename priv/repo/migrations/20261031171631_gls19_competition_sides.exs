defmodule GolfScoring.Repo.Migrations.Gls19CompetitionSides do
  @moduledoc false

  use Ecto.Migration

  def up do
    create table(:round_competitions, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:is_primary, :boolean, null: false, default: true)
      add(:scoring_policy_identifier, :text, null: false, default: "four_ball_stableford_v1")
      add(:handicap_allowance_percent, :bigint, null: false, default: 100)
      add(:solo_sides_permitted, :boolean, null: false, default: false)
      add(:solo_normalization_policy_identifier, :text,
        null: false,
        default: "companion_max_p_minus_one_v1"
      )
      add(:pickup_policy_identifier, :text, null: false, default: "standard_pickup_v1")
      add(:competition_terms_reference, :text)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(
        :event_id,
        references(:events,
          column: :id,
          name: "round_competitions_event_id_fkey",
          type: :uuid,
          on_delete: :restrict
        ),
        null: false
      )

      add(:round_id, :uuid, null: false)
    end

    alter table(:round_competitions) do
      modify(
        :round_id,
        references(:rounds,
          column: :id,
          with: [event_id: :event_id],
          name: "round_competitions_round_id_fkey",
          type: :uuid,
          on_delete: :restrict
        )
      )
    end

    create unique_index(:round_competitions, [:round_id],
             name: "round_competitions_one_primary_per_round_index",
             where: "is_primary = true"
           )

    create unique_index(:round_competitions, [:id, :round_id],
             name: "round_competitions_unique_id_per_round_index"
           )

    create constraint(:round_competitions, :round_competitions_scoring_policy_must_be_present,
             check: "btrim(scoring_policy_identifier) <> ''"
           )

    create index(:round_competitions, [:round_id])
    create index(:round_competitions, [:event_id])

    create table(:competition_sides, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:formation, :text, null: false)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:round_competition_id, :uuid, null: false)
      add(:round_id, :uuid, null: false)
    end

    alter table(:competition_sides) do
      modify(
        :round_id,
        references(:rounds,
          column: :id,
          name: "competition_sides_round_id_fkey",
          type: :uuid,
          on_delete: :restrict
        )
      )

      modify(
        :round_competition_id,
        references(:round_competitions,
          column: :id,
          with: [round_id: :round_id],
          name: "competition_sides_round_competition_id_fkey",
          type: :uuid,
          on_delete: :restrict
        )
      )
    end

    create unique_index(:competition_sides, [:id, :round_id, :round_competition_id],
             name: "competition_sides_unique_id_per_round_competition_index"
           )

    create constraint(:competition_sides, :competition_sides_formation_must_be_valid,
             check: "formation IN ('partnership', 'solo')"
           )

    create index(:competition_sides, [:round_competition_id])
    create index(:competition_sides, [:round_id])

    create table(:competition_side_results, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:state, :text, null: false, default: "provisional")

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(
        :competition_side_id,
        references(:competition_sides,
          column: :id,
          name: "competition_side_results_competition_side_id_fkey",
          type: :uuid,
          on_delete: :restrict
        ),
        null: false
      )
    end

    create unique_index(:competition_side_results, [:competition_side_id],
             name: "competition_side_results_unique_side_index"
           )

    create constraint(:competition_side_results, :competition_side_results_state_must_be_valid,
             check:
               "state IN ('provisional', 'review_required', 'ready_to_finalize', 'finalized', 'excluded')"
           )

    create index(:competition_side_results, [:competition_side_id])

    create table(:competition_side_memberships, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:round_competition_id, :uuid, null: false)
      add(:competition_side_id, :uuid, null: false)
      add(:round_entry_id, :uuid, null: false)
      add(:round_id, :uuid, null: false)
    end

    alter table(:competition_side_memberships) do
      modify(
        :round_id,
        references(:rounds,
          column: :id,
          name: "competition_side_memberships_round_id_fkey",
          type: :uuid,
          on_delete: :restrict
        )
      )

      modify(
        :round_competition_id,
        references(:round_competitions,
          column: :id,
          with: [round_id: :round_id],
          name: "competition_side_memberships_round_competition_id_fkey",
          type: :uuid,
          on_delete: :restrict
        )
      )

      modify(
        :competition_side_id,
        references(:competition_sides,
          column: :id,
          with: [round_id: :round_id, round_competition_id: :round_competition_id],
          name: "competition_side_memberships_competition_side_id_fkey",
          type: :uuid,
          on_delete: :restrict
        )
      )

      modify(
        :round_entry_id,
        references(:round_entries,
          column: :id,
          with: [round_id: :round_id],
          name: "competition_side_memberships_round_entry_id_fkey",
          type: :uuid,
          on_delete: :restrict
        )
      )
    end

    create unique_index(:competition_side_memberships, [:round_competition_id, :round_entry_id],
             name: "competition_side_memberships_unique_entry_per_competition_index"
           )

    create index(:competition_side_memberships, [:round_competition_id])
    create index(:competition_side_memberships, [:competition_side_id])
    create index(:competition_side_memberships, [:round_entry_id])
    create index(:competition_side_memberships, [:round_id])
  end

  def down do
    drop(table(:competition_side_memberships))
    drop(table(:competition_side_results))
    drop(table(:competition_sides))
    drop(table(:round_competitions))
  end
end
