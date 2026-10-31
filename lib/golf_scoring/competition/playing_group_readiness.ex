defmodule GolfScoring.Competition.PlayingGroupReadiness do
  @moduledoc false

  @setup_capacity_max 4
  @starting_readiness_min 2
  @starting_readiness_max 4

  @spec setup_capacity_max() :: pos_integer()
  def setup_capacity_max, do: @setup_capacity_max

  @spec starting_readiness_min() :: pos_integer()
  def starting_readiness_min, do: @starting_readiness_min

  @spec starting_readiness_max() :: pos_integer()
  def starting_readiness_max, do: @starting_readiness_max

  @spec setup_capacity_allowed?(non_neg_integer()) :: boolean()
  def setup_capacity_allowed?(count) when is_integer(count) and count >= 0 and count <= 4,
    do: true

  def setup_capacity_allowed?(_), do: false

  @spec starting_ready?(non_neg_integer()) :: boolean()
  def starting_ready?(count) when is_integer(count) and count in 2..4, do: true
  def starting_ready?(_), do: false
end
