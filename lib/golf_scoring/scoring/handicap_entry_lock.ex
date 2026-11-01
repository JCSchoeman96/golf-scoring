defmodule GolfScoring.Scoring.HandicapEntryLock do
  @moduledoc false

  alias GolfScoring.Repo

  @spec lock!(Ecto.UUID.t()) ::
          {:ok, map()} | {:error, :round_entry_not_found | :entry_not_not_started}
  def lock!(round_entry_id) do
    case Repo.query!(
           """
           SELECT id::text, event_id::text, round_id::text, player_id::text,
                  participation_status, round_tee_profile_snapshot_id::text
           FROM round_entries
           WHERE id = $1::uuid
           FOR UPDATE
           """,
           [Ecto.UUID.dump!(round_entry_id)]
         ).rows do
      [[id, event_id, round_id, _player_id, participation, tee_snapshot_id]] ->
        entry = %{
          id: Ecto.UUID.cast!(id),
          event_id: Ecto.UUID.cast!(event_id),
          round_id: Ecto.UUID.cast!(round_id),
          participation_status: String.to_existing_atom(participation),
          round_tee_profile_snapshot_id: cast_optional_uuid(tee_snapshot_id)
        }

        if entry.participation_status == :not_started do
          {:ok, entry}
        else
          {:error, :entry_not_not_started}
        end

      [] ->
        {:error, :round_entry_not_found}
    end
  end

  def cast_optional_uuid(nil), do: nil

  def cast_optional_uuid(value) do
    {:ok, uuid} = Ecto.UUID.cast(value)
    uuid
  end
end
