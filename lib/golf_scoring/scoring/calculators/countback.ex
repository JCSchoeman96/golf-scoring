defmodule GolfScoring.Scoring.Calculators.Countback do
  @moduledoc """
  Pure deterministic countback tie-break keys from per-hole track contributions.
  """

  @valid_policies [:standard_countback, :mystery_holes_then_countback]

  @standard_ranges [
    10..18,
    13..18,
    16..18,
    [18],
    4..9,
    7..9,
    [9]
  ]

  @required_keys [:physical_hole_number, :points, :mystery_hole?]

  @doc """
  Builds a deterministic tie-break key from eighteen per-hole contributions.

  Returns `{:ok, %{tie_break_key: key}}` or `{:error, :invalid_input}` /
  `{:error, :unsupported_policy}`.
  """
  @spec calculate([map()], :standard_countback | :mystery_holes_then_countback) ::
          {:ok, %{tie_break_key: [non_neg_integer()]}}
          | {:error, :invalid_input | :unsupported_policy}
  def calculate(_contributions, policy) when policy not in @valid_policies do
    {:error, :unsupported_policy}
  end

  def calculate(contributions, _policy) when not is_list(contributions) do
    {:error, :invalid_input}
  end

  def calculate(contributions, policy) when is_list(contributions) do
    with {:ok, by_hole} <- index_contributions(contributions) do
      key =
        case policy do
          :standard_countback ->
            standard_key(by_hole)

          :mystery_holes_then_countback ->
            [mystery_subtotal(contributions) | standard_key(by_hole)]
        end

      {:ok, %{tie_break_key: key}}
    end
  end

  defp index_contributions(contributions) when length(contributions) != 18 do
    {:error, :invalid_input}
  end

  defp index_contributions(contributions) do
    contributions
    |> Enum.reduce_while({:ok, %{}}, &accumulate_contribution/2)
    |> finalize_hole_index()
  end

  defp accumulate_contribution(contribution, {:ok, acc}) do
    case validate_contribution(contribution) do
      :ok ->
        hole = contribution.physical_hole_number

        if Map.has_key?(acc, hole) do
          {:halt, {:error, :invalid_input}}
        else
          {:cont, {:ok, Map.put(acc, hole, contribution.points)}}
        end

      :error ->
        {:halt, {:error, :invalid_input}}
    end
  end

  defp finalize_hole_index({:ok, by_hole}) do
    if complete_hole_set?(by_hole), do: {:ok, by_hole}, else: {:error, :invalid_input}
  end

  defp finalize_hole_index({:error, :invalid_input} = error), do: error

  defp complete_hole_set?(by_hole) do
    map_size(by_hole) == 18 and Enum.sort(Map.keys(by_hole)) == Enum.to_list(1..18)
  end

  defp validate_contribution(contribution) do
    cond do
      not is_map(contribution) ->
        :error

      not Enum.all?(@required_keys, &Map.has_key?(contribution, &1)) ->
        :error

      not valid_hole_number?(contribution.physical_hole_number) ->
        :error

      not valid_points?(contribution.points) ->
        :error

      not is_boolean(contribution.mystery_hole?) ->
        :error

      true ->
        :ok
    end
  end

  defp valid_hole_number?(hole) when is_integer(hole) and hole >= 1 and hole <= 18, do: true
  defp valid_hole_number?(_), do: false

  defp valid_points?(points) when is_integer(points) and points >= 0, do: true
  defp valid_points?(_), do: false

  defp mystery_subtotal(contributions) do
    contributions
    |> Enum.filter(& &1.mystery_hole?)
    |> Enum.map(& &1.points)
    |> Enum.sum()
  end

  defp standard_key(by_hole) do
    Enum.map(@standard_ranges, &sum_range(by_hole, &1))
  end

  defp sum_range(by_hole, first..last//_) do
    Enum.reduce(first..last, 0, fn hole, acc -> acc + Map.fetch!(by_hole, hole) end)
  end

  defp sum_range(by_hole, [hole]), do: Map.fetch!(by_hole, hole)
end
