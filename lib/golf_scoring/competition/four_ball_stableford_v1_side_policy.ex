defmodule GolfScoring.Competition.FourBallStablefordV1SidePolicy do
  @moduledoc false

  alias GolfScoring.Competition.StartingParticipant

  @spec validate_membership(map(), atom(), [map()]) :: :ok | {:error, atom()}
  def validate_membership(%{solo_sides_permitted: solo?}, formation, entries)
      when formation in [:partnership, :solo] and is_list(entries) do
    with :ok <- validate_unique_member_ids(entries),
         :ok <- validate_all_current_starters(entries) do
      validate_formation_cardinality(formation, solo?, entries)
    end
  end

  def validate_membership(_competition, _formation, _entries), do: {:error, :invalid_formation}

  defp validate_unique_member_ids(entries) do
    member_ids = Enum.map(entries, & &1.id)

    if length(member_ids) == length(Enum.uniq(member_ids)) do
      :ok
    else
      {:error, :duplicate_member_ids}
    end
  end

  defp validate_all_current_starters(entries) do
    if Enum.all?(entries, &StartingParticipant.current_starting_participant?/1) do
      :ok
    else
      {:error, :not_current_starting_participant}
    end
  end

  defp validate_formation_cardinality(:partnership, _solo?, entries) do
    if starter_count(entries) == 2 do
      :ok
    else
      {:error, :invalid_side_cardinality}
    end
  end

  defp validate_formation_cardinality(:solo, false, _entries), do: {:error, :solo_not_permitted}

  defp validate_formation_cardinality(:solo, true, entries) do
    if starter_count(entries) == 1 do
      :ok
    else
      {:error, :invalid_side_cardinality}
    end
  end

  defp starter_count(entries) do
    Enum.count(entries, &StartingParticipant.current_starting_participant?/1)
  end
end
