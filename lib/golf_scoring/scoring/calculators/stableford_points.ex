defmodule GolfScoring.Scoring.Calculators.StablefordPoints do
  @moduledoc """
  Pure Stableford / IPS competition points from hole outcome, par and allocated strokes.
  """

  @doc """
  Derives competition Stableford points without mutating gross stroke facts.

  Returns `{:ok, result_map}` or `{:error, atom}`.
  """
  @spec calculate(map()) :: {:ok, map()} | {:error, atom()}
  def calculate(%{outcome: :picked_up} = input) do
    case Map.get(input, :gross_strokes) do
      nil ->
        {:ok,
         %{
           competition_points: 0,
           gross_strokes: nil
         }}

      _ ->
        {:error, :invalid_outcome_gross_combination}
    end
  end

  def calculate(%{outcome: :holed_out} = input) do
    with gross_strokes when is_integer(gross_strokes) and gross_strokes > 0 <-
           Map.get(input, :gross_strokes),
         par when is_integer(par) <- Map.get(input, :par),
         allocated_strokes when is_integer(allocated_strokes) <-
           Map.get(input, :allocated_strokes) do
      competition_net_strokes = gross_strokes - allocated_strokes
      competition_points = points_for_net(competition_net_strokes, par)

      {:ok,
       %{
         competition_points: competition_points,
         competition_net_strokes: competition_net_strokes,
         gross_strokes: gross_strokes
       }}
    else
      _ -> {:error, :invalid_outcome_gross_combination}
    end
  end

  def calculate(_input), do: {:error, :invalid_input}

  defp points_for_net(competition_net_strokes, par) do
    net_over_par = competition_net_strokes - par
    points = 2 - net_over_par
    max(0, points)
  end
end
