defmodule GolfScoring.Competition.Services.ConfigureRoundCompetition do
  @moduledoc false

  require Ash.Query

  alias Ash.Changeset
  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Competition.RoundCompetition
  alias GolfScoring.Repo

  @manager_roles [:event_admin, :competition_manager]
  @pre_open_round_states ~w(draft ready)

  @spec run(map(), Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, RoundCompetition.t()} | {:error, term()}
  def run(actor, event_id, round_id, attrs) when is_map(actor) and is_map(attrs) do
    actor_id = Map.get(actor, :id)

    Repo.transaction(fn ->
      with {:ok, _scope} <- EventAuthorityLock.lock_scope!(event_id, [actor_id]),
           :ok <- authorize(actor_id, event_id),
           {:ok, round} <- lock_round(round_id),
           :ok <- round_belongs_to_event(round, event_id),
           :ok <- round_accepts_configuration(round),
           {:ok, competition} <- upsert_primary(round, attrs) do
        competition
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_result()
  end

  def run(_actor, _event_id, _round_id, _attrs), do: {:error, :invalid_input}

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

  defp upsert_primary(round, attrs) do
    case RoundCompetition
         |> Ash.Query.filter(round_id == ^round.id and is_primary == true)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        RoundCompetition
        |> Changeset.for_create(:configure_internal, build_create_attrs(round, attrs))
        |> Ash.create(authorize?: false)

      {:ok, existing} ->
        existing
        |> Changeset.for_update(:update_configuration_internal, build_update_attrs(attrs))
        |> Ash.update(authorize?: false)

      {:error, error} ->
        {:error, error}
    end
  end

  defp build_create_attrs(round, attrs) do
    %{
      event_id: round.event_id,
      round_id: round.id,
      is_primary: true,
      scoring_policy_identifier:
        Map.get(attrs, :scoring_policy_identifier, "four_ball_stableford_v1"),
      handicap_allowance_percent: Map.get(attrs, :handicap_allowance_percent, 100),
      solo_sides_permitted: Map.get(attrs, :solo_sides_permitted, false),
      solo_normalization_policy_identifier:
        Map.get(attrs, :solo_normalization_policy_identifier, "companion_max_p_minus_one_v1"),
      pickup_policy_identifier: Map.get(attrs, :pickup_policy_identifier, "standard_pickup_v1"),
      competition_terms_reference: Map.get(attrs, :competition_terms_reference)
    }
  end

  defp build_update_attrs(attrs) do
    attrs
    |> Map.take([
      :solo_sides_permitted,
      :handicap_allowance_percent,
      :solo_normalization_policy_identifier,
      :pickup_policy_identifier,
      :competition_terms_reference
    ])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_result({:ok, result}), do: {:ok, result}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result({:error, :rollback, reason}), do: {:error, reason}
end
