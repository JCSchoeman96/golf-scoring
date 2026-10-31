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

  @spec starting_participant_count_valid?(non_neg_integer()) :: boolean()
  def starting_participant_count_valid?(count) when is_integer(count) and count in 2..4, do: true
  def starting_participant_count_valid?(_), do: false

  @spec group_setup_complete?(non_neg_integer(), map()) :: boolean()
  def group_setup_complete?(current_starting_count, playing_group) do
    starting_participant_count_valid?(current_starting_count) and
      start_assignment_present?(playing_group)
  end

  defp start_assignment_present?(%{
         starting_round_hole_id: hole_id,
         starting_position: position
       })
       when not is_nil(hole_id) and not is_nil(position),
       do: true

  defp start_assignment_present?(_), do: false
end
