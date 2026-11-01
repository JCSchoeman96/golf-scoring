defmodule GolfScoring.Competition.Services.ConfigureMysteryHoleRule do
  @moduledoc false

  require Ash.Query

  alias Ash.Changeset
  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Competition.MysteryHoleRule
  alias GolfScoring.Competition.ScoringTrack
  alias GolfScoring.Repo

  @manager_roles [:event_admin, :competition_manager]
  @pre_open_round_states ~w(draft ready)

  @spec run(map(), Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), atom()) ::
          {:ok, MysteryHoleRule.t()} | {:error, term()}
  def run(actor, event_id, round_id, scoring_track_id, round_hole_id, rule)
      when is_map(actor) and rule in [:best, :worst, :both] do
    actor_id = Map.get(actor, :id)

    Repo.transaction(fn ->
      with {:ok, _scope} <- EventAuthorityLock.lock_scope!(event_id, [actor_id]),
           :ok <- authorize(actor_id, event_id),
           {:ok, round} <- lock_round(round_id),
           :ok <- round_belongs_to_event(round, event_id),
           :ok <- round_accepts_configuration(round),
           {:ok, track} <- load_scoring_track(scoring_track_id, round_id),
           :ok <- mystery_track_required(track),
           :ok <- lock_round_hole(round_hole_id, round_id),
           {:ok, rule_row} <- upsert_mystery_hole_rule(track, round_hole_id, round_id, rule) do
        rule_row
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_result()
  end

  def run(_actor, _event_id, _round_id, _track_id, _hole_id, _rule), do: {:error, :invalid_input}

  @spec remove(map(), Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          :ok | {:error, term()}
  def remove(actor, event_id, round_id, scoring_track_id, round_hole_id) when is_map(actor) do
    actor_id = Map.get(actor, :id)

    Repo.transaction(fn ->
      with {:ok, _scope} <- EventAuthorityLock.lock_scope!(event_id, [actor_id]),
           :ok <- authorize(actor_id, event_id),
           {:ok, round} <- lock_round(round_id),
           :ok <- round_belongs_to_event(round, event_id),
           :ok <- round_accepts_configuration(round),
           {:ok, track} <- load_scoring_track(scoring_track_id, round_id),
           :ok <- mystery_track_required(track),
           :ok <- lock_round_hole(round_hole_id, round_id),
           :ok <- destroy_mystery_hole_rule(track, round_hole_id) do
        :ok
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_remove_result()
  end

  def remove(_actor, _event_id, _round_id, _track_id, _hole_id), do: {:error, :invalid_input}

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

  defp round_accepts_configuration(%{state: state}) when state in @pre_open_round_states, do: :ok

  defp round_accepts_configuration(%{state: state}),
    do: {:error, {:invalid_round_state, state}}

  defp load_scoring_track(scoring_track_id, round_id) do
    case ScoringTrack
         |> Ash.Query.filter(id == ^scoring_track_id and round_id == ^round_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, %ScoringTrack{configuration_state: :locked}} ->
        {:error, :configuration_locked}

      {:ok, %ScoringTrack{} = track} ->
        {:ok, track}

      {:ok, nil} ->
        {:error, :scoring_track_not_found}

      {:error, error} ->
        {:error, error}
    end
  end

  defp mystery_track_required(%ScoringTrack{track_type: :mystery}), do: :ok
  defp mystery_track_required(%ScoringTrack{}), do: {:error, :mystery_track_required}

  defp lock_round_hole(round_hole_id, round_id) do
    case Repo.query!(
           "SELECT id::text FROM round_holes WHERE id = $1::uuid AND round_id = $2::uuid",
           [Ecto.UUID.dump!(round_hole_id), Ecto.UUID.dump!(round_id)]
         ).rows do
      [[_id]] -> :ok
      [] -> {:error, :round_hole_not_found}
    end
  end

  defp upsert_mystery_hole_rule(track, round_hole_id, round_id, rule) do
    case MysteryHoleRule
         |> Ash.Query.filter(scoring_track_id == ^track.id and round_hole_id == ^round_hole_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        MysteryHoleRule
        |> Changeset.for_create(:configure_mystery_hole_rule_internal, %{
          scoring_track_id: track.id,
          round_hole_id: round_hole_id,
          round_id: round_id,
          rule: rule
        })
        |> Ash.create(authorize?: false)

      {:ok, existing} ->
        existing
        |> Changeset.for_update(:update_mystery_hole_rule_internal, %{rule: rule})
        |> Ash.update(authorize?: false)

      {:error, error} ->
        {:error, error}
    end
  end

  defp destroy_mystery_hole_rule(track, round_hole_id) do
    case MysteryHoleRule
         |> Ash.Query.filter(scoring_track_id == ^track.id and round_hole_id == ^round_hole_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        {:error, :mystery_hole_rule_not_found}

      {:ok, rule} ->
        case Ash.destroy(rule, action: :remove_mystery_hole_rule_internal, authorize?: false) do
          :ok -> :ok
          {:ok, _} -> :ok
          {:error, error} -> {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp normalize_result({:ok, result}), do: {:ok, result}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result({:error, :rollback, reason}), do: {:error, reason}

  defp normalize_remove_result({:ok, :ok}), do: :ok
  defp normalize_remove_result({:error, reason}), do: {:error, reason}
  defp normalize_remove_result({:error, :rollback, reason}), do: {:error, reason}
end
