defmodule GolfScoring.Competition.CompetitionSideGroupCohesion do
  @moduledoc false

  alias GolfScoring.Competition.StartingParticipant

  @spec validate([map()], keyword()) :: :ok | {:error, :competition_side_split_across_groups}
  def validate(entries, opts \\ []) do
    if split_across_groups?(entries, opts) do
      {:error, :competition_side_split_across_groups}
    else
      :ok
    end
  end

  @spec split_across_groups?([map()], keyword()) :: boolean()
  def split_across_groups?(entries, opts \\ []) do
    moving_entry_id = Keyword.get(opts, :moving_entry_id)
    target_group_id = Keyword.get(opts, :target_group_id)

    entries
    |> Enum.filter(&StartingParticipant.current_starting_participant?/1)
    |> then(fn starters ->
      if length(starters) < 2 do
        false
      else
        starters
        |> Enum.map(&effective_playing_group_id(&1, moving_entry_id, target_group_id))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> then(&(length(&1) > 1))
      end
    end)
  end

  defp effective_playing_group_id(
         %{id: id, playing_group_id: group_id},
         moving_entry_id,
         target_group_id
       ) do
    if moving_entry_id && id == moving_entry_id do
      target_group_id
    else
      group_id
    end
  end
end
