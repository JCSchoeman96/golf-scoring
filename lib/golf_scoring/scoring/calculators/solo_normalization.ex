defmodule GolfScoring.Scoring.Calculators.SoloNormalization do
  @moduledoc """
  Pure solo-side contributor normalization for a single eligible Stableford value.
  """

  @doc """
  Derives normalized contributor data for solo-fairness scoring.

  For player points `P`, the companion is `max(P - 1, 0)` and
  `normalized_contributors` is `[P, companion]`.

  Returns `{:ok, result_map}` or `{:error, :invalid_input}` when `player_points`
  is not a non-negative integer.
  """
  @spec normalize(non_neg_integer()) ::
          {:ok,
           %{
             player_points: non_neg_integer(),
             companion_points: non_neg_integer(),
             normalized_contributors: [non_neg_integer(), ...]
           }}
          | {:error, :invalid_input}
  def normalize(player_points)
      when is_integer(player_points) and player_points >= 0 do
    companion_points = max(player_points - 1, 0)

    {:ok,
     %{
       player_points: player_points,
       companion_points: companion_points,
       normalized_contributors: [player_points, companion_points]
     }}
  end

  def normalize(_), do: {:error, :invalid_input}
end
