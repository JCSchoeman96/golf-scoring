defmodule GolfScoring.Scoring.HandicapRowLock do
  @moduledoc false

  alias GolfScoring.Repo

  @spec lock_handicap_snapshot!(Ecto.UUID.t()) ::
          {:ok, map() | nil} | {:error, term()}
  def lock_handicap_snapshot!(round_entry_id) do
    case Repo.query!(
           """
           SELECT id::text, round_id::text, round_entry_id::text,
                  round_tee_profile_snapshot_id::text, built_at
           FROM handicap_snapshots
           WHERE round_entry_id = $1::uuid
           FOR UPDATE
           """,
           [Ecto.UUID.dump!(round_entry_id)]
         ).rows do
      [] ->
        {:ok, nil}

      [[id, round_id, entry_id, tee_id, built_at]] ->
        {:ok,
         %{
           id: Ecto.UUID.cast!(id),
           round_id: Ecto.UUID.cast!(round_id),
           round_entry_id: Ecto.UUID.cast!(entry_id),
           round_tee_profile_snapshot_id: Ecto.UUID.cast!(tee_id),
           built_at: built_at
         }}
    end
  end

  @spec lock_round_competition!(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, map()} | {:error, :round_competition_not_found}
  def lock_round_competition!(round_competition_id, round_id) do
    case Repo.query!(
           """
           SELECT id::text, round_id::text, handicap_allowance_percent
           FROM round_competitions
           WHERE id = $1::uuid AND round_id = $2::uuid
           FOR UPDATE
           """,
           [
             Ecto.UUID.dump!(round_competition_id),
             Ecto.UUID.dump!(round_id)
           ]
         ).rows do
      [[id, rid, allowance]] ->
        {:ok,
         %{
           id: Ecto.UUID.cast!(id),
           round_id: Ecto.UUID.cast!(rid),
           handicap_allowance_percent: allowance
         }}

      [] ->
        {:error, :round_competition_not_found}
    end
  end
end
