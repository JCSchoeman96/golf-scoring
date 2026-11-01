defmodule GolfScoring.Scoring.Calculators.FourBallBest do
  @moduledoc """
  Pure Four-Ball better-ball side contribution from two eligible Stableford values.
  """

  @doc """
  Returns the better-ball side contribution as `max(player_a_points, player_b_points)`.

  Both inputs must be non-negative integers. Returns `{:ok, %{best_points: integer}}`
  or `{:error, :invalid_input}`.
  """
  @spec calculate(non_neg_integer(), non_neg_integer()) ::
          {:ok, %{best_points: non_neg_integer()}} | {:error, :invalid_input}
  def calculate(player_a_points, player_b_points)
      when is_integer(player_a_points) and player_a_points >= 0 and
             is_integer(player_b_points) and player_b_points >= 0 do
    {:ok, %{best_points: max(player_a_points, player_b_points)}}
  end

  def calculate(_, _), do: {:error, :invalid_input}
end
