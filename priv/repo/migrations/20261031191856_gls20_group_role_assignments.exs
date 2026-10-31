defmodule GolfScoring.Repo.Migrations.Gls20GroupRoleAssignments do
  @moduledoc false

  use Ecto.Migration

  def up do
    create table(:group_role_assignments, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:role, :text, null: false)
      add(:state, :text, null: false, default: "active")
      add(:assignment_version, :bigint, null: false)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(:updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(
        :round_id,
        references(:rounds,
          column: :id,
          name: "group_role_assignments_round_id_fkey",
          type: :uuid,
          on_delete: :restrict
        ),
        null: false
      )

      add(:playing_group_id, :uuid, null: false)
      add(:round_entry_id, :uuid, null: false)
    end

    alter table(:group_role_assignments) do
      modify(
        :playing_group_id,
        references(:playing_groups,
          column: :id,
          with: [round_id: :round_id],
          name: "group_role_assignments_playing_group_id_fkey",
          type: :uuid,
          on_delete: :restrict
        )
      )

      modify(
        :round_entry_id,
        references(:round_entries,
          column: :id,
          with: [round_id: :round_id],
          name: "group_role_assignments_round_entry_id_fkey",
          type: :uuid,
          on_delete: :restrict
        )
      )
    end

    create index(:group_role_assignments, [:playing_group_id, :role, :assignment_version],
             name: "group_role_assignments_unique_revision_index",
             unique: true
           )

    create index(:group_role_assignments, [:playing_group_id, :round_entry_id],
             name: "group_role_assignments_one_active_entry_per_group_index",
             unique: true,
             where: "state = 'active'"
           )

    create index(:group_role_assignments, [:playing_group_id, :role],
             name: "group_role_assignments_one_active_per_group_role_index",
             unique: true,
             where: "state = 'active'"
           )

    create constraint(:group_role_assignments, :group_role_assignments_role_must_be_valid,
             check: "role IN ('primary_scorer', 'designated_verifier')"
           )

    create constraint(:group_role_assignments, :group_role_assignments_state_must_be_valid,
             check: "state IN ('active', 'handed_over', 'revoked')"
           )

    create constraint(:group_role_assignments, :group_role_assignments_version_must_be_positive,
             check: "assignment_version > 0"
           )

    create index(:group_role_assignments, [:round_id])
    create index(:group_role_assignments, [:playing_group_id])
    create index(:group_role_assignments, [:round_entry_id])
  end

  def down do
    drop table(:group_role_assignments)
  end
end
