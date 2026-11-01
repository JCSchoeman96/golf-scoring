defmodule GolfScoring.Scoring.Policies.PickupEligibility do
  @moduledoc """
  Player-local pickup eligibility for competition Stableford holes.
  """

  alias GolfScoring.Scoring.Calculators.StablefordPoints

  @standard_pickup_v1 "standard_pickup_v1"
  @allowed_context_keys ~w(pickup_policy_identifier par allocated_strokes strokes_taken)a

  @doc """
  Decides whether a player may pick up on the current hole.

  Returns `{:ok, %{eligible?: boolean, reason: atom}}` or `{:error, atom}`.
  """
  @spec decide(map()) :: {:ok, map()} | {:error, atom()}
  def decide(%{pickup_policy_identifier: @standard_pickup_v1} = input) do
    with :ok <- validate_player_local_context(input),
         par when is_integer(par) <- Map.get(input, :par),
         allocated_strokes when is_integer(allocated_strokes) <-
           Map.get(input, :allocated_strokes),
         strokes_taken when is_integer(strokes_taken) and strokes_taken >= 0 <-
           Map.get(input, :strokes_taken),
         {:ok, %{competition_points: points}} <-
           StablefordPoints.calculate(%{
             outcome: :holed_out,
             gross_strokes: strokes_taken + 1,
             par: par,
             allocated_strokes: allocated_strokes
           }) do
      if points >= 1 do
        {:ok, %{eligible?: false, reason: :point_still_possible}}
      else
        {:ok, %{eligible?: true, reason: :no_point_possible}}
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_context}
    end
  end

  def decide(%{pickup_policy_identifier: policy}) when is_binary(policy) do
    {:error, :unsupported_pickup_policy}
  end

  def decide(_input), do: {:error, :invalid_context}

  defp validate_player_local_context(input) do
    extra_keys =
      input
      |> Map.keys()
      |> Enum.reject(&(&1 in @allowed_context_keys))

    if extra_keys == [] do
      :ok
    else
      {:error, :invalid_context}
    end
  end
end
