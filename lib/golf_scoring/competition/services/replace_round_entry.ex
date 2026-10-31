defmodule GolfScoring.Competition.Services.ReplaceRoundEntry do
  @moduledoc false

  alias Ash.Changeset
  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Competition.Player
  alias GolfScoring.Competition.RoundEntry
  alias GolfScoring.Repo

  @manager_roles [:event_admin, :competition_manager]
  @pre_open_round_states ~w(draft ready)

  @spec run(map(), Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, %{original: RoundEntry.t(), replacement: RoundEntry.t()}} | {:error, term()}
  def run(actor, event_id, round_id, original_entry_id, replacement_player_id)
      when is_map(actor) do
    actor_id = Map.get(actor, :id)

    Repo.transaction(fn ->
      with {:ok, _scope} <- EventAuthorityLock.lock_scope!(event_id, [actor_id]),
           :ok <- authorize(actor_id, event_id),
           {:ok, round} <- lock_round(round_id),
           :ok <- round_belongs_to_event(round, event_id),
           :ok <- round_accepts_replacement(round),
           {:ok, original} <- lock_round_entry(original_entry_id),
           :ok <- original_belongs_to_round(original, round_id, event_id),
           :ok <- validate_original(original, replacement_player_id),
           :ok <- replacement_player_exists(replacement_player_id),
           :ok <- replacement_available(round_id, replacement_player_id),
           {:ok, marked} <- mark_original_replaced(original.id),
           {:ok, replacement} <- create_replacement(actor, marked, replacement_player_id) do
        %{original: marked, replacement: replacement}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_result()
  end

  def run(_actor, _event_id, _round_id, _original_entry_id, _replacement_player_id),
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

  defp round_accepts_replacement(%{state: state}) when state in @pre_open_round_states, do: :ok
  defp round_accepts_replacement(%{state: state}), do: {:error, {:invalid_round_state, state}}

  defp lock_round_entry(round_entry_id) do
    case Repo.query!(
           """
           SELECT id::text, event_id::text, round_id::text, player_id::text,
                  registration_status, participation_status
           FROM round_entries
           WHERE id = $1::uuid
           FOR UPDATE
           """,
           [Ecto.UUID.dump!(round_entry_id)]
         ).rows do
      [[id, event_id, round_id, player_id, registration_status, participation_status]] ->
        {:ok,
         %{
           id: Ecto.UUID.cast!(id),
           event_id: Ecto.UUID.cast!(event_id),
           round_id: Ecto.UUID.cast!(round_id),
           player_id: Ecto.UUID.cast!(player_id),
           registration_status: registration_atom(registration_status),
           participation_status: participation_atom(participation_status)
         }}

      [] ->
        {:error, :round_entry_not_found}
    end
  end

  defp original_belongs_to_round(original, round_id, event_id) do
    if original.round_id == round_id and original.event_id == event_id do
      :ok
    else
      {:error, :round_entry_mismatch}
    end
  end

  defp validate_original(original, replacement_player_id) do
    cond do
      original.registration_status in [:no_show, :withdrawn_before_start, :replaced_before_start] ->
        {:error, :terminal_registration}

      original.participation_status != :not_started ->
        {:error, :participation_started}

      original.registration_status not in [:expected, :checked_in] ->
        {:error, :invalid_registration}

      original.player_id == replacement_player_id ->
        {:error, :same_player}

      true ->
        :ok
    end
  end

  defp replacement_player_exists(player_id) do
    if Repo.get(Player, player_id), do: :ok, else: {:error, :player_not_found}
  end

  defp replacement_available(round_id, replacement_player_id) do
    case Repo.query!(
           "SELECT 1 FROM round_entries WHERE round_id = $1::uuid AND player_id = $2::uuid LIMIT 1",
           [Ecto.UUID.dump!(round_id), Ecto.UUID.dump!(replacement_player_id)]
         ).rows do
      [] -> :ok
      [_row] -> {:error, :replacement_already_entered}
    end
  end

  defp mark_original_replaced(original_id) do
    case Repo.query!(
           """
           UPDATE round_entries
           SET registration_status = 'replaced_before_start', updated_at = (NOW() AT TIME ZONE 'UTC')
           WHERE id = $1::uuid
             AND registration_status IN ('expected', 'checked_in')
             AND participation_status = 'not_started'
           RETURNING id::text
           """,
           [Ecto.UUID.dump!(original_id)]
         ).rows do
      [[_id]] -> {:ok, Ash.get!(RoundEntry, original_id, authorize?: false)}
      [] -> {:error, :mark_original_failed}
    end
  end

  defp create_replacement(actor, original, replacement_player_id) do
    RoundEntry
    |> Changeset.for_create(:add_round_entry, %{
      event_id: original.event_id,
      round_id: original.round_id,
      player_id: replacement_player_id
    })
    |> Changeset.put_context(:gls16_skip_entry_authorization, true)
    |> Ash.create(actor: actor, authorize?: false)
    |> case do
      {:ok, entry} -> {:ok, entry}
      {:error, error} -> {:error, error}
    end
  end

  defp normalize_result({:ok, result}), do: {:ok, result}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result({:error, :rollback, reason}), do: {:error, reason}

  defp registration_atom("expected"), do: :expected
  defp registration_atom("checked_in"), do: :checked_in
  defp registration_atom("no_show"), do: :no_show
  defp registration_atom("withdrawn_before_start"), do: :withdrawn_before_start
  defp registration_atom("replaced_before_start"), do: :replaced_before_start

  defp participation_atom("not_started"), do: :not_started
  defp participation_atom("active"), do: :active
  defp participation_atom("completed"), do: :completed
  defp participation_atom("withdrawn"), do: :withdrawn
  defp participation_atom("disqualified"), do: :disqualified
end
