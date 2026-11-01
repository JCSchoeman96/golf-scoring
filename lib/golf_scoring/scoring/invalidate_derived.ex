defmodule GolfScoring.Scoring.InvalidateDerived do
  @moduledoc false

  require Ash.Query

  alias Ash.Changeset
  alias GolfScoring.Scoring.CompetitionHandicap
  alias GolfScoring.Scoring.HandicapSnapshot

  @spec for_entry(Ecto.UUID.t()) :: :ok | {:error, term()}
  def for_entry(round_entry_id) do
    with :ok <- destroy_competition_handicaps(round_entry_id),
         :ok <- invalidate_snapshot_built_values(round_entry_id) do
      :ok
    end
  end

  defp destroy_competition_handicaps(round_entry_id) do
    CompetitionHandicap
    |> Ash.Query.filter(round_entry_id == ^round_entry_id)
    |> Ash.read!(authorize?: false)
    |> Enum.reduce_while(:ok, fn row, :ok ->
      case Ash.destroy(row, action: :destroy_prestart_internal, authorize?: false) do
        :ok -> {:cont, :ok}
        {:ok, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp invalidate_snapshot_built_values(round_entry_id) do
    case HandicapSnapshot
         |> Ash.Query.filter(round_entry_id == ^round_entry_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        :ok

      {:ok, snapshot} ->
        if is_nil(snapshot.built_at) do
          :ok
        else
          snapshot
          |> Changeset.for_update(:invalidate_built_internal, %{})
          |> Ash.update(authorize?: false)
          |> case do
            {:ok, _} -> :ok
            {:error, error} -> {:error, error}
          end
        end

      {:error, error} ->
        {:error, error}
    end
  end
end
