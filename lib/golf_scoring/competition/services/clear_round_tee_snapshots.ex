defmodule GolfScoring.Competition.Services.ClearRoundTeeSnapshots do
  @moduledoc false

  alias GolfScoring.Accounts.Checks.ActiveEventRole
  alias GolfScoring.Accounts.EventAuthorityLock
  alias GolfScoring.Competition.RoundTeeHoleSnapshot
  alias GolfScoring.Competition.RoundTeeProfileSnapshot
  alias GolfScoring.Repo

  @clear_roles [:event_admin, :competition_manager]
  @allowed_states ~w(draft ready)

  @spec run(map(), Ecto.UUID.t()) :: {:ok, []} | {:error, term()}
  def run(actor, round_id) when is_map(actor) do
    actor_id = Map.get(actor, :id)

    Repo.transaction(fn ->
      with {:ok, preliminary_round} <- fetch_round(round_id),
           {:ok, _scope} <-
             EventAuthorityLock.lock_scope!(preliminary_round.event_id, [actor_id]),
           {:ok, round} <- lock_round(round_id),
           :ok <- authorize(actor_id, round.event_id),
           :ok <- round_accepts_clear(round),
           :ok <- remove_all_snapshots(round.id) do
        :ok
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_result()
  end

  def run(_actor, _round_id), do: {:error, :invalid_input}

  defp fetch_round(round_id) do
    case round_row(round_id) do
      nil -> {:error, :round_not_found}
      round -> {:ok, round}
    end
  end

  defp round_row(round_id) do
    case Repo.query!(
           "SELECT id::text, event_id::text, course_id::text, state FROM rounds WHERE id = $1::uuid",
           [Ecto.UUID.dump!(round_id)]
         ).rows do
      [[id, event_id, course_id, state]] ->
        %{
          id: Ecto.UUID.cast!(id),
          event_id: Ecto.UUID.cast!(event_id),
          course_id: Ecto.UUID.cast!(course_id),
          state: state
        }

      [] ->
        nil
    end
  end

  defp lock_round(round_id) do
    case round_row_for_update(round_id) do
      nil -> {:error, :round_not_found}
      round -> {:ok, round}
    end
  end

  defp round_row_for_update(round_id) do
    case Repo.query!(
           "SELECT id::text, event_id::text, course_id::text, state FROM rounds WHERE id = $1::uuid FOR UPDATE",
           [Ecto.UUID.dump!(round_id)]
         ).rows do
      [[id, event_id, course_id, state]] ->
        %{
          id: Ecto.UUID.cast!(id),
          event_id: Ecto.UUID.cast!(event_id),
          course_id: Ecto.UUID.cast!(course_id),
          state: state
        }

      [] ->
        nil
    end
  end

  defp authorize(actor_id, event_id) do
    if ActiveEventRole.authorized?(actor_id, event_id, @clear_roles) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp round_accepts_clear(%{state: state}) when state in @allowed_states, do: :ok

  defp round_accepts_clear(%{state: state}), do: {:error, {:invalid_round_state, state}}

  defp remove_all_snapshots(round_id) do
    profile_rows =
      Repo.query!(
        """
        SELECT id::text
        FROM round_tee_profile_snapshots
        WHERE round_id = $1::uuid
        ORDER BY id
        FOR UPDATE
        """,
        [Ecto.UUID.dump!(round_id)]
      ).rows

    Enum.each(profile_rows, fn [snapshot_id] ->
      snapshot_id = Ecto.UUID.cast!(snapshot_id)
      remove_hole_snapshots(snapshot_id, round_id)
      remove_profile_snapshot(snapshot_id)
    end)

    :ok
  end

  defp remove_hole_snapshots(snapshot_id, round_id) do
    rows =
      Repo.query!(
        """
        SELECT id::text
        FROM round_tee_hole_snapshots
        WHERE round_tee_profile_snapshot_id = $1::uuid AND round_id = $2::uuid
        ORDER BY id
        FOR UPDATE
        """,
        [Ecto.UUID.dump!(snapshot_id), Ecto.UUID.dump!(round_id)]
      ).rows

    Enum.each(rows, fn [id] ->
      RoundTeeHoleSnapshot
      |> Ash.get!(Ecto.UUID.cast!(id), authorize?: false)
      |> Ash.Changeset.for_destroy(:remove_hole_snapshot, %{})
      |> Ash.destroy!(authorize?: false)
    end)
  end

  defp remove_profile_snapshot(snapshot_id) do
    RoundTeeProfileSnapshot
    |> Ash.get!(snapshot_id, authorize?: false)
    |> Ash.Changeset.for_destroy(:remove_snapshot, %{})
    |> Ash.destroy!(authorize?: false)
  end

  defp normalize_result({:ok, :ok}), do: {:ok, []}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result(other), do: other
end
