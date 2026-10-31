defmodule GolfScoring.Competition.FourBallStablefordV1SidePolicy do
  @moduledoc false

  alias GolfScoring.Competition.StartingParticipant

  @spec validate_membership(map(), atom(), [map()]) :: :ok | {:error, atom()}
  def validate_membership(%{solo_sides_permitted: solo?}, formation, entries)
      when formation in [:partnership, :solo] and is_list(entries) do
    starter_count = Enum.count(entries, &StartingParticipant.current_starting_participant?/1)
    member_ids = Enum.map(entries, & &1.id)

    cond do
      length(member_ids) != length(Enum.uniq(member_ids)) ->
        {:error, :duplicate_member_ids}

      not Enum.all?(entries, &StartingParticipant.current_starting_participant?/1) ->
        {:error, :not_current_starting_participant}

      formation == :partnership and starter_count != 2 ->
        {:error, :invalid_side_cardinality}

      formation == :solo and not solo? ->
        {:error, :solo_not_permitted}

      formation == :solo and starter_count != 1 ->
        {:error, :invalid_side_cardinality}

      true ->
        :ok
    end
  end

  def validate_membership(_competition, _formation, _entries), do: {:error, :invalid_formation}
end
