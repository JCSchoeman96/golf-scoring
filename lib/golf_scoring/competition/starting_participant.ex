defmodule GolfScoring.Competition.StartingParticipant do
  @moduledoc false

  @current_registration ~w(expected checked_in)
  @table_refs %{round_entries: "round_entries", re: "re"}

  @registration_statuses_sql ~s('expected', 'checked_in')
  @participation_status_sql ~s('not_started')

  @sql_predicate """
                 registration_status IN (#{@registration_statuses_sql})
                 AND participation_status = #{@participation_status_sql}
                 """
                 |> String.trim()

  @count_starters_in_group_excluding_entry_sql """
  SELECT count(*)::int
  FROM round_entries
  WHERE playing_group_id = $1::uuid
    AND id <> $2::uuid
    AND #{@sql_predicate}
  """

  @list_current_starters_in_round_sql """
  SELECT id::text, playing_group_id::text
  FROM round_entries
  WHERE round_id = $1::uuid
    AND #{@sql_predicate}
  ORDER BY id
  """

  @count_starters_in_group_sql """
  SELECT count(*)::int FROM round_entries
  WHERE playing_group_id = $1::uuid
    AND #{@sql_predicate}
  """

  @spec current_starting_participant?(map()) :: boolean()
  def current_starting_participant?(%{registration_status: reg, participation_status: part}) do
    registration_eligible?(reg) and participation_not_started?(part)
  end

  def current_starting_participant?(_), do: false

  @spec count_starters_in_group_excluding_entry(Ecto.Repo.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          non_neg_integer()
  def count_starters_in_group_excluding_entry(repo, group_id, entry_id) do
    [[count]] =
      repo.query!(@count_starters_in_group_excluding_entry_sql, [
        Ecto.UUID.dump!(group_id),
        Ecto.UUID.dump!(entry_id)
      ]).rows

    count
  end

  @spec list_current_starters_in_round(Ecto.Repo.t(), Ecto.UUID.t()) :: [
          %{id: String.t(), playing_group_id: Ecto.UUID.t() | nil}
        ]
  def list_current_starters_in_round(repo, round_id) do
    repo.query!(@list_current_starters_in_round_sql, [Ecto.UUID.dump!(round_id)]).rows
    |> Enum.map(fn [id, group_id] ->
      %{id: id, playing_group_id: cast_optional_uuid(group_id)}
    end)
  end

  defp registration_eligible?(reg) when reg in [:expected, :checked_in], do: true
  defp registration_eligible?(reg) when is_binary(reg), do: reg in @current_registration
  defp registration_eligible?(_), do: false

  defp participation_not_started?(:not_started), do: true
  defp participation_not_started?("not_started"), do: true
  defp participation_not_started?(_), do: false

  @spec sql_predicate() :: String.t()
  def sql_predicate, do: @sql_predicate

  @spec sql_where_fragment(:round_entries | :re) :: String.t()
  def sql_where_fragment(table_ref) when is_atom(table_ref) do
    table = Map.fetch!(@table_refs, table_ref)

    """
    #{table}.registration_status IN (#{@registration_statuses_sql})
    AND #{table}.participation_status = #{@participation_status_sql}
    """
    |> String.trim()
  end

  @spec count_starters_in_group_sql() :: String.t()
  def count_starters_in_group_sql, do: @count_starters_in_group_sql

  @spec count_starters_in_group_excluding_entry_query() :: String.t()
  def count_starters_in_group_excluding_entry_query,
    do: @count_starters_in_group_excluding_entry_sql

  @spec list_current_starters_in_round_query() :: String.t()
  def list_current_starters_in_round_query, do: @list_current_starters_in_round_sql

  defp cast_optional_uuid(nil), do: nil

  defp cast_optional_uuid(value) do
    {:ok, uuid} = Ecto.UUID.cast(value)
    uuid
  end
end
