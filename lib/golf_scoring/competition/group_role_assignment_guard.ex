defmodule GolfScoring.Competition.GroupRoleAssignmentGuard do
  @moduledoc false

  alias GolfScoring.Repo

  @active_state "active"

  @spec entry_has_active_assignment?(Ecto.Repo.t(), Ecto.UUID.t()) :: boolean()
  def entry_has_active_assignment?(repo \\ Repo, round_entry_id) do
    case repo.query!(
           """
           SELECT EXISTS (
             SELECT 1 FROM group_role_assignments
             WHERE round_entry_id = $1::uuid AND state = $2
           )
           """,
           [Ecto.UUID.dump!(round_entry_id), @active_state]
         ).rows do
      [[true]] -> true
      [[false]] -> false
    end
  end

  @spec active_assignment_blocks_group_move?(map(), Ecto.UUID.t()) :: boolean()
  def active_assignment_blocks_group_move?(entry, target_group_id) do
    current = Map.get(entry, :playing_group_id)

    current != nil and current != target_group_id and entry_has_active_assignment?(Repo, entry.id)
  end

  @spec reject_active_role_group_move(map(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def reject_active_role_group_move(entry, target_group_id) do
    if active_assignment_blocks_group_move?(entry, target_group_id) do
      {:error, :active_group_role_assignment_blocks_group_move}
    else
      :ok
    end
  end

  @spec reject_active_role_registration_transition(Ecto.UUID.t()) :: :ok | {:error, atom()}
  def reject_active_role_registration_transition(round_entry_id) do
    if entry_has_active_assignment?(Repo, round_entry_id) do
      {:error, :active_group_role_assignment_blocks_registration_transition}
    else
      :ok
    end
  end

  @spec reject_active_role_replacement(Ecto.UUID.t()) :: :ok | {:error, atom()}
  def reject_active_role_replacement(round_entry_id) do
    if entry_has_active_assignment?(Repo, round_entry_id) do
      {:error, :active_group_role_assignment_blocks_replacement}
    else
      :ok
    end
  end

  @spec lock_active_assignment_for_group_role(Ecto.Repo.t(), Ecto.UUID.t(), atom()) ::
          {:ok, map()} | {:error, :no_active_assignment} | {:error, :assignment_not_found}
  def lock_active_assignment_for_group_role(repo, playing_group_id, role) do
    role_str = to_string(role)

    case repo.query!(
           """
           SELECT id::text, round_id::text, playing_group_id::text, round_entry_id::text,
                  role, state, assignment_version
           FROM group_role_assignments
           WHERE playing_group_id = $1::uuid AND role = $2 AND state = $3
           FOR UPDATE
           """,
           [Ecto.UUID.dump!(playing_group_id), role_str, @active_state]
         ).rows do
      [[id, round_id, group_id, entry_id, db_role, state, version]] ->
        {:ok,
         %{
           id: Ecto.UUID.cast!(id),
           round_id: Ecto.UUID.cast!(round_id),
           playing_group_id: Ecto.UUID.cast!(group_id),
           round_entry_id: Ecto.UUID.cast!(entry_id),
           role: String.to_existing_atom(db_role),
           state: String.to_existing_atom(state),
           assignment_version: version
         }}

      [] ->
        {:error, :no_active_assignment}
    end
  end

  @spec entry_holds_other_active_role?(Ecto.Repo.t(), Ecto.UUID.t(), Ecto.UUID.t(), atom()) ::
          boolean()
  def entry_holds_other_active_role?(repo, playing_group_id, round_entry_id, excluding_role) do
    excluding = to_string(excluding_role)

    case repo.query!(
           """
           SELECT EXISTS (
             SELECT 1 FROM group_role_assignments
             WHERE playing_group_id = $1::uuid
               AND round_entry_id = $2::uuid
               AND state = $3
               AND role <> $4
           )
           """,
           [
             Ecto.UUID.dump!(playing_group_id),
             Ecto.UUID.dump!(round_entry_id),
             @active_state,
             excluding
           ]
         ).rows do
      [[true]] -> true
      [[false]] -> false
    end
  end

  @spec next_assignment_version(Ecto.Repo.t(), Ecto.UUID.t(), atom()) :: pos_integer()
  def next_assignment_version(repo, playing_group_id, role) do
    [[max]] =
      repo.query!(
        """
        SELECT COALESCE(MAX(assignment_version), 0)::int
        FROM group_role_assignments
        WHERE playing_group_id = $1::uuid AND role = $2
        """,
        [Ecto.UUID.dump!(playing_group_id), to_string(role)]
      ).rows

    max + 1
  end

  @spec lock_active_assignments_for_group(Ecto.Repo.t(), Ecto.UUID.t()) :: :ok
  def lock_active_assignments_for_group(repo, playing_group_id) do
    _ =
      repo.query!(
        """
        SELECT id FROM group_role_assignments
        WHERE playing_group_id = $1::uuid AND state = $2
        ORDER BY id
        FOR UPDATE
        """,
        [Ecto.UUID.dump!(playing_group_id), @active_state]
      )

    :ok
  end
end
