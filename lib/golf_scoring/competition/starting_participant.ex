defmodule GolfScoring.Competition.StartingParticipant do
  @moduledoc false

  @current_registration ~w(expected checked_in)

  @spec current_starting_participant?(map()) :: boolean()
  def current_starting_participant?(%{registration_status: reg, participation_status: part}) do
    registration_eligible?(reg) and participation_not_started?(part)
  end

  def current_starting_participant?(_), do: false

  defp registration_eligible?(reg) when reg in [:expected, :checked_in], do: true
  defp registration_eligible?(reg) when is_binary(reg), do: reg in @current_registration
  defp registration_eligible?(_), do: false

  defp participation_not_started?(:not_started), do: true
  defp participation_not_started?("not_started"), do: true
  defp participation_not_started?(_), do: false

  @spec sql_where_fragment(String.t()) :: String.t()
  def sql_where_fragment(table \\ "round_entries") do
    """
    #{table}.registration_status IN ('expected', 'checked_in')
    AND #{table}.participation_status = 'not_started'
    """
  end

  @spec count_starters_in_group_sql() :: String.t()
  def count_starters_in_group_sql do
    """
    SELECT count(*)::int FROM round_entries
    WHERE playing_group_id = $1::uuid
      AND registration_status IN ('expected', 'checked_in')
      AND participation_status = 'not_started'
    """
  end
end
