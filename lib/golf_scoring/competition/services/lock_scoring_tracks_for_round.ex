defmodule GolfScoring.Competition.Services.LockScoringTracksForRound do
  @moduledoc false

  require Ash.Query

  alias Ash.Changeset
  alias GolfScoring.Competition.ScoringTrack

  @spec run(Ecto.UUID.t()) :: :ok | {:error, term()}
  def run(round_id) do
    tracks =
      ScoringTrack
      |> Ash.Query.filter(round_id == ^round_id and configuration_state == :draft)
      |> Ash.read!(authorize?: false)

    Enum.reduce_while(tracks, :ok, fn track, :ok ->
      case track
           |> Changeset.for_update(:lock_configuration_internal, %{})
           |> Ash.update(authorize?: false) do
        {:ok, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
