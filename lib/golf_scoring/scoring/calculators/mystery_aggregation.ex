defmodule GolfScoring.Scoring.Calculators.MysteryAggregation do
  @moduledoc """
  Pure Mystery hole aggregation from already-eligible Stableford point contributions.
  """

  @valid_rules [:best, :worst, :both]

  @doc """
  Aggregates eligible Stableford point contributions for a Mystery rule.

  Returns `{:ok, %{mystery_points: integer}}` or one of:

    * `{:error, :no_contributions}` — empty contribution list
    * `{:error, :unsupported_rule}` — rule is not `:best`, `:worst`, or `:both`
    * `{:error, :invalid_input}` — malformed contributions container or values
  """
  @spec calculate([non_neg_integer()], :best | :worst | :both) ::
          {:ok, %{mystery_points: non_neg_integer()}}
          | {:error, :no_contributions | :unsupported_rule | :invalid_input}
  def calculate([], _rule), do: {:error, :no_contributions}

  def calculate(contributions, rule) when is_list(contributions) do
    with :ok <- validate_contributions(contributions),
         :ok <- validate_rule(rule) do
      {:ok, %{mystery_points: aggregate(contributions, rule)}}
    end
  end

  def calculate(_contributions, _rule), do: {:error, :invalid_input}

  defp validate_contributions(contributions) do
    if Enum.all?(contributions, &valid_contribution?/1) do
      :ok
    else
      {:error, :invalid_input}
    end
  end

  defp valid_contribution?(value) when is_integer(value) and value >= 0, do: true
  defp valid_contribution?(_), do: false

  defp validate_rule(rule) when rule in @valid_rules, do: :ok
  defp validate_rule(_), do: {:error, :unsupported_rule}

  defp aggregate(contributions, :best), do: Enum.max(contributions)
  defp aggregate(contributions, :worst), do: Enum.min(contributions)
  defp aggregate(contributions, :both), do: Enum.sum(contributions)
end
