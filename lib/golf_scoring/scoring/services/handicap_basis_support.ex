defmodule GolfScoring.Scoring.Services.HandicapBasisSupport do
  @moduledoc false

  require Ash.Query

  alias Ash.Changeset
  alias GolfScoring.Scoring.HandicapSnapshot
  alias GolfScoring.Scoring.InvalidateDerived

  @spec upsert_configured!(map(), map()) :: {:ok, HandicapSnapshot.t()} | {:error, term()}
  def upsert_configured!(entry, attrs) do
    with :ok <- InvalidateDerived.for_entry(entry.id) do
      upsert_after_invalidation(entry, attrs)
    end
  end

  defp upsert_after_invalidation(entry, attrs) do
    case HandicapSnapshot
         |> Ash.Query.filter(round_entry_id == ^entry.id)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        HandicapSnapshot
        |> Changeset.for_create(:create_configured_internal, Map.merge(base_ids(entry), attrs))
        |> Ash.create(authorize?: false)

      {:ok, snapshot} ->
        snapshot
        |> Changeset.for_update(
          :update_basis_internal,
          Map.merge(%{round_tee_profile_snapshot_id: entry.round_tee_profile_snapshot_id}, attrs)
        )
        |> force_nil_attributes(attrs)
        |> Ash.update(authorize?: false)

      {:error, error} ->
        {:error, error}
    end
  end

  defp base_ids(entry) do
    %{
      round_id: entry.round_id,
      round_entry_id: entry.id,
      round_tee_profile_snapshot_id: entry.round_tee_profile_snapshot_id
    }
  end

  defp force_nil_attributes(changeset, attrs) do
    Enum.reduce(attrs, changeset, fn
      {key, nil}, acc -> Ash.Changeset.force_change_attribute(acc, key, nil)
      _, acc -> acc
    end)
  end
end
