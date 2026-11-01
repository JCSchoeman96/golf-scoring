defmodule GolfScoring.Scoring.InvalidateDerived do
  @moduledoc false

  require Ash.Query

  alias Ash.Changeset
  alias GolfScoring.Scoring.CompetitionHandicap
  alias GolfScoring.Scoring.HandicapRowLock
  alias GolfScoring.Scoring.HandicapSnapshot

  @spec for_entry(Ecto.UUID.t()) :: :ok | {:error, term()}
  def for_entry(round_entry_id) do
    invalidate_derived_state(round_entry_id, nil)
  end

  @spec realign_entry_tee!(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, term()}
  def realign_entry_tee!(round_entry_id, round_tee_profile_snapshot_id) do
    invalidate_derived_state(round_entry_id, round_tee_profile_snapshot_id)
  end

  defp invalidate_derived_state(round_entry_id, tee_snapshot_id) do
    with :ok <- destroy_competition_handicaps(round_entry_id) do
      realign_or_clear_snapshot(round_entry_id, tee_snapshot_id)
    end
  end

  defp destroy_competition_handicaps(round_entry_id) do
    rows =
      CompetitionHandicap
      |> Ash.Query.filter(round_entry_id == ^round_entry_id)
      |> Ash.read!(authorize?: false)

    Enum.reduce_while(rows, :ok, &destroy_competition_row/2)
  end

  defp destroy_competition_row(row, :ok) do
    case Ash.destroy(row, action: :destroy_prestart_internal, authorize?: false) do
      :ok -> {:cont, :ok}
      {:ok, _} -> {:cont, :ok}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp realign_or_clear_snapshot(round_entry_id, tee_snapshot_id) do
    case HandicapRowLock.lock_handicap_snapshot!(round_entry_id) do
      {:ok, nil} ->
        :ok

      {:ok, locked} ->
        apply_snapshot_realignment(locked, tee_snapshot_id)
    end
  end

  defp apply_snapshot_realignment(locked, tee_snapshot_id) do
    snapshot = Ash.get!(HandicapSnapshot, locked.id, authorize?: false)

    attrs =
      if tee_snapshot_id do
        %{round_tee_profile_snapshot_id: tee_snapshot_id}
      else
        %{}
      end

    snapshot
    |> Changeset.for_update(:realign_round_tee_internal, attrs)
    |> Ash.update(authorize?: false)
    |> case do
      {:ok, _} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
