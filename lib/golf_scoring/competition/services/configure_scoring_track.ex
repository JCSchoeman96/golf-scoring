defmodule GolfScoring.Competition.Services.ConfigureScoringTrack do
  @moduledoc false

  require Ash.Query

  alias Ash.Changeset
  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Competition.ScoringTrack
  alias GolfScoring.Repo

  @manager_roles [:event_admin, :competition_manager]
  @pre_open_round_states ~w(draft ready)

  @spec run(map(), Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, ScoringTrack.t()} | {:error, term()}
  def run(actor, event_id, round_id, round_competition_id, attrs)
      when is_map(actor) and is_map(attrs) do
    actor_id = Map.get(actor, :id)

    Repo.transaction(fn ->
      with {:ok, _scope} <- EventAuthorityLock.lock_scope!(event_id, [actor_id]),
           :ok <- authorize(actor_id, event_id),
           {:ok, round} <- lock_round(round_id),
           :ok <- round_belongs_to_event(round, event_id),
           :ok <- round_accepts_configuration(round),
           {:ok, competition} <- lock_round_competition(round_competition_id, round_id),
           {:ok, track} <- upsert_scoring_track(competition, round, attrs) do
        track
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_result()
  end

  def run(_actor, _event_id, _round_id, _round_competition_id, _attrs),
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

  defp round_accepts_configuration(%{state: state}) when state in @pre_open_round_states, do: :ok

  defp round_accepts_configuration(%{state: state}),
    do: {:error, {:invalid_round_state, state}}

  defp lock_round_competition(round_competition_id, round_id) do
    case Repo.query!(
           """
           SELECT id::text, event_id::text, round_id::text
           FROM round_competitions
           WHERE id = $1::uuid AND round_id = $2::uuid
           FOR UPDATE
           """,
           [Ecto.UUID.dump!(round_competition_id), Ecto.UUID.dump!(round_id)]
         ).rows do
      [[id, event_id, round_id_text]] ->
        {:ok,
         %{
           id: Ecto.UUID.cast!(id),
           event_id: Ecto.UUID.cast!(event_id),
           round_id: Ecto.UUID.cast!(round_id_text)
         }}

      [] ->
        {:error, :round_competition_not_found}
    end
  end

  defp upsert_scoring_track(competition, round, attrs) do
    scoring_track_id = Map.get(attrs, :scoring_track_id)

    create_attrs = %{
      event_id: competition.event_id,
      round_id: round.id,
      round_competition_id: competition.id,
      track_type: Map.get(attrs, :track_type),
      name: Map.get(attrs, :name),
      is_primary: Map.get(attrs, :is_primary, false),
      visibility_policy_identifier: Map.get(attrs, :visibility_policy_identifier),
      aggregation_policy_identifier: Map.get(attrs, :aggregation_policy_identifier),
      tie_break_policy_identifier: Map.get(attrs, :tie_break_policy_identifier),
      configuration_state: :draft
    }

    update_attrs =
      attrs
      |> Map.take([
        :name,
        :is_primary,
        :visibility_policy_identifier,
        :aggregation_policy_identifier,
        :tie_break_policy_identifier
      ])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    if scoring_track_id do
      update_scoring_track(scoring_track_id, competition.id, update_attrs, attrs)
    else
      ScoringTrack
      |> Changeset.for_create(:configure_scoring_track_internal, create_attrs)
      |> Ash.create(authorize?: false)
    end
  end

  defp update_scoring_track(scoring_track_id, round_competition_id, update_attrs, attrs) do
    case Ash.get(ScoringTrack, scoring_track_id, authorize?: false) do
      {:ok,
       %ScoringTrack{round_competition_id: ^round_competition_id, configuration_state: :draft} =
           existing} ->
        apply_scoring_track_update(existing, update_attrs, attrs)

      {:ok, %ScoringTrack{configuration_state: :locked}} ->
        {:error, :configuration_locked}

      {:ok, %ScoringTrack{}} ->
        {:error, :round_competition_mismatch}

      {:error, error} ->
        {:error, error}
    end
  end

  defp apply_scoring_track_update(existing, update_attrs, attrs) do
    with :ok <- ensure_track_type_unchanged(existing, attrs) do
      existing
      |> Changeset.for_update(:update_scoring_track_configuration_internal, update_attrs)
      |> Ash.update(authorize?: false)
    end
  end

  defp ensure_track_type_unchanged(%ScoringTrack{track_type: persisted}, attrs) do
    case Map.fetch(attrs, :track_type) do
      :error -> :ok
      {:ok, ^persisted} -> :ok
      {:ok, _other} -> {:error, :track_type_immutable}
    end
  end

  defp normalize_result({:ok, result}), do: {:ok, result}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result({:error, :rollback, reason}), do: {:error, reason}
end
