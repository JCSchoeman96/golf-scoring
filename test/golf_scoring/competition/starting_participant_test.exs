defmodule GolfScoring.Competition.StartingParticipantTest do
  use ExUnit.Case, async: true

  alias GolfScoring.Competition.StartingParticipant

  test "current_starting_participant?/1 classifies registration and participation pairs" do
    assert StartingParticipant.current_starting_participant?(%{
             registration_status: :expected,
             participation_status: :not_started
           })

    assert StartingParticipant.current_starting_participant?(%{
             registration_status: :checked_in,
             participation_status: :not_started
           })

    refute StartingParticipant.current_starting_participant?(%{
             registration_status: :no_show,
             participation_status: :not_started
           })

    refute StartingParticipant.current_starting_participant?(%{
             registration_status: :withdrawn_before_start,
             participation_status: :not_started
           })

    refute StartingParticipant.current_starting_participant?(%{
             registration_status: :replaced_before_start,
             participation_status: :not_started
           })

    refute StartingParticipant.current_starting_participant?(%{
             registration_status: :expected,
             participation_status: :active
           })

    refute StartingParticipant.current_starting_participant?(%{
             registration_status: :expected,
             participation_status: :completed
           })
  end

  test "SQL helpers compose one shared predicate" do
    predicate = StartingParticipant.sql_predicate()

    assert predicate =~ "registration_status IN ('expected', 'checked_in')"
    assert predicate =~ "participation_status = 'not_started'"

    assert StartingParticipant.count_starters_in_group_sql() =~ predicate
    assert StartingParticipant.count_starters_in_group_excluding_entry_query() =~ predicate
    assert StartingParticipant.list_current_starters_in_round_query() =~ predicate

    assert StartingParticipant.sql_where_fragment(:round_entries) =~
             "round_entries.registration_status IN ('expected', 'checked_in')"

    assert StartingParticipant.sql_where_fragment(:re) =~
             "re.participation_status = 'not_started'"
  end
end
