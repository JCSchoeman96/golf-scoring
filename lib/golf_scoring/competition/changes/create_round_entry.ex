defmodule GolfScoring.Competition.Changes.CreateRoundEntry do
  @moduledoc false

  use Ash.Resource.Change

  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Competition.Player
  alias GolfScoring.Repo

  @manager_roles [:event_admin, :competition_manager]
  @pre_open_round_states ~w(draft ready)

  @impl true
  def change(changeset, _opts, context) do
    actor_id = if is_map(context.actor), do: Map.get(context.actor, :id), else: nil

    Ash.Changeset.before_action(changeset, fn changeset ->
      event_id = Ash.Changeset.get_attribute(changeset, :event_id)
      round_id = Ash.Changeset.get_attribute(changeset, :round_id)
      player_id = Ash.Changeset.get_attribute(changeset, :player_id)

      with {:ok, _scope} <- EventAuthorityLock.lock_scope!(event_id, [actor_id]),
           :ok <- maybe_authorize(changeset, actor_id, event_id),
           {:ok, round} <- lock_round(round_id),
           :ok <- round_belongs_to_event(round, event_id),
           :ok <- round_accepts_new_entry(round),
           :ok <- player_exists(player_id) do
        changeset
        |> Ash.Changeset.force_change_attribute(:registration_status, :expected)
        |> Ash.Changeset.force_change_attribute(:participation_status, :not_started)
      else
        {:error, message} ->
          Ash.Changeset.add_error(changeset, field: :round_id, message: message)
      end
    end)
  end

  defp maybe_authorize(changeset, actor_id, event_id) do
    if Map.get(changeset.context, :gls16_skip_entry_authorization) do
      :ok
    else
      authorize(actor_id, event_id)
    end
  end

  defp authorize(actor_id, event_id) do
    if ActiveEventRole.authorized?(actor_id, event_id, @manager_roles) do
      :ok
    else
      {:error, "an active EventAdmin or CompetitionManager assignment for this Event is required"}
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
        {:error, "Round does not exist"}
    end
  end

  defp round_belongs_to_event(round, event_id) do
    if round.event_id == event_id do
      :ok
    else
      {:error, "Round does not belong to the requested Event"}
    end
  end

  defp round_accepts_new_entry(%{state: state}) when state in @pre_open_round_states, do: :ok

  defp round_accepts_new_entry(%{state: state}) do
    {:error, "cannot add a RoundEntry while the Round is #{state}"}
  end

  defp player_exists(player_id) do
    case Repo.get(Player, player_id) do
      nil -> {:error, "Player does not exist"}
      _player -> :ok
    end
  end
end
