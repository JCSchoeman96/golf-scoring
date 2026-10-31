defmodule GolfScoring.Competition.Services.AssignEntryToGroup do
  @moduledoc false

  alias Ash.Changeset
  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Competition.PlayingGroupReadiness
  alias GolfScoring.Competition.RoundEntry
  alias GolfScoring.Competition.StartingParticipant
  alias GolfScoring.Repo

  @manager_roles [:event_admin, :competition_manager]
  @pre_open_round_states ~w(draft ready)

  @spec run(map(), Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, RoundEntry.t()} | {:error, term()}
  def run(actor, event_id, round_id, round_entry_id, playing_group_id)
      when is_map(actor) do
    actor_id = Map.get(actor, :id)

    Repo.transaction(fn ->
      with {:ok, _scope} <- EventAuthorityLock.lock_scope!(event_id, [actor_id]),
           :ok <- authorize(actor_id, event_id),
           {:ok, round} <- lock_round(round_id),
           :ok <- round_belongs_to_event(round, event_id),
           :ok <- round_accepts_assignment(round),
           {:ok, group} <- lock_playing_group(playing_group_id),
           :ok <- group_belongs_to_round(group, round_id),
           {:ok, entry} <- lock_round_entry(round_entry_id),
           :ok <- entry_belongs_to_round(entry, round_id, event_id),
           :ok <- validate_start_eligible(entry),
           :ok <- validate_capacity(group.id, entry),
           {:ok, updated} <- assign_entry(entry, group.id) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_result()
  end

  def run(_actor, _event_id, _round_id, _round_entry_id, _playing_group_id),
    do: {:error, :invalid_input}

  defp authorize(actor_id, event_id) do
    if ActiveEventRole.authorized?(actor_id, event_id, @manager_roles) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp lock_round(round_id) do
    case Repo.query!(
           "SELECT id::text, event_id::text, state FROM rounds WHERE id = $1::uuid FOR UPDATE",
           [Ecto.UUID.dump!(round_id)]
         ).rows do
      [[id, event_id, state]] ->
        {:ok,
         %{
           id: Ecto.UUID.cast!(id),
           event_id: Ecto.UUID.cast!(event_id),
           state: state
         }}

      [] ->
        {:error, :round_not_found}
    end
  end

  defp round_belongs_to_event(%{event_id: round_event_id}, event_id) do
    if round_event_id == event_id, do: :ok, else: {:error, :event_mismatch}
  end

  defp round_accepts_assignment(%{state: state}) when state in @pre_open_round_states, do: :ok

  defp round_accepts_assignment(%{state: state}),
    do: {:error, {:invalid_round_state, state}}

  defp lock_playing_group(playing_group_id) do
    case Repo.query!(
           """
           SELECT id::text, round_id::text
           FROM playing_groups
           WHERE id = $1::uuid
           FOR UPDATE
           """,
           [Ecto.UUID.dump!(playing_group_id)]
         ).rows do
      [[id, round_id]] ->
        {:ok, %{id: Ecto.UUID.cast!(id), round_id: Ecto.UUID.cast!(round_id)}}

      [] ->
        {:error, :playing_group_not_found}
    end
  end

  defp group_belongs_to_round(%{round_id: group_round_id}, round_id) do
    if group_round_id == round_id, do: :ok, else: {:error, :playing_group_mismatch}
  end

  defp lock_round_entry(round_entry_id) do
    case Repo.query!(
           """
           SELECT id::text, event_id::text, round_id::text, player_id::text,
                  registration_status, participation_status, playing_group_id::text
           FROM round_entries
           WHERE id = $1::uuid
           FOR UPDATE
           """,
           [Ecto.UUID.dump!(round_entry_id)]
         ).rows do
      [[id, event_id, round_id, player_id, registration_status, participation_status, group_id]] ->
        {:ok,
         %{
           id: Ecto.UUID.cast!(id),
           event_id: Ecto.UUID.cast!(event_id),
           round_id: Ecto.UUID.cast!(round_id),
           player_id: Ecto.UUID.cast!(player_id),
           registration_status: registration_status,
           participation_status: participation_status,
           playing_group_id: cast_optional_uuid(group_id)
         }}

      [] ->
        {:error, :round_entry_not_found}
    end
  end

  defp cast_optional_uuid(nil), do: nil

  defp cast_optional_uuid(value) do
    {:ok, uuid} = Ecto.UUID.cast(value)
    uuid
  end

  defp entry_belongs_to_round(entry, round_id, event_id) do
    if entry.round_id == round_id and entry.event_id == event_id do
      :ok
    else
      {:error, :round_entry_mismatch}
    end
  end

  defp validate_start_eligible(entry) do
    if StartingParticipant.current_starting_participant?(entry) do
      :ok
    else
      {:error, :not_current_starting_participant}
    end
  end

  defp validate_capacity(group_id, %{playing_group_id: current, id: _entry_id} = entry)
       when current == group_id do
    if StartingParticipant.current_starting_participant?(entry) do
      :ok
    else
      {:error, :not_current_starting_participant}
    end
  end

  defp validate_capacity(group_id, entry) do
    count = StartingParticipant.count_starters_in_group_excluding_entry(Repo, group_id, entry.id)

    if count + 1 > PlayingGroupReadiness.setup_capacity_max() do
      {:error, :group_capacity_exceeded}
    else
      :ok
    end
  end

  defp assign_entry(%{id: entry_id, playing_group_id: current_group_id}, playing_group_id)
       when current_group_id == playing_group_id do
    case Ash.get(RoundEntry, entry_id, authorize?: false) do
      {:ok, entry} -> {:ok, entry}
      {:error, error} -> {:error, error}
    end
  end

  defp assign_entry(entry, playing_group_id) do
    case Ash.get(RoundEntry, entry.id, authorize?: false) do
      {:ok, record} ->
        record
        |> Changeset.for_update(:assign_playing_group_internal, %{
          playing_group_id: playing_group_id
        })
        |> Ash.update(authorize?: false)

      {:error, error} ->
        {:error, error}
    end
  end

  defp normalize_result({:ok, result}), do: {:ok, result}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result({:error, :rollback, reason}), do: {:error, reason}
end
