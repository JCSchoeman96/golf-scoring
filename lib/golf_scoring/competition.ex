defmodule GolfScoring.Competition do
  @moduledoc "Competition and Event lifecycle domain."

  use Ash.Domain

  resources do
    resource GolfScoring.Competition.Event do
      define :cancel_event, action: :cancel_event
      define :archive_event, action: :archive_event
    end

    resource GolfScoring.Competition.Round do
      define :create_round, action: :create_round, args: [:event_id, :course_id]
      define :get_round_by_id, action: :read, get_by: [:id]
      define :mark_round_ready, action: :mark_round_ready
      define :open_scoring, action: :open_scoring
      define :close_scoring, action: :close_scoring
      define :finalize_round, action: :finalize_round
      define :reopen_round, action: :reopen_round, args: [:reason]
      define :cancel_round, action: :cancel_round
    end

    resource GolfScoring.Competition.RoundHole

    resource GolfScoring.Competition.RoundTeeProfileSnapshot
    resource GolfScoring.Competition.RoundTeeHoleSnapshot

    resource GolfScoring.Competition.Player

    resource GolfScoring.Competition.CompetitionCategory
    resource GolfScoring.Competition.RoundEntryCategoryMembership

    resource GolfScoring.Competition.RoundEntry do
      define :add_round_entry, action: :add_round_entry, args: [:event_id, :round_id, :player_id]
      define :check_in_round_entry, action: :check_in_round_entry
      define :mark_no_show, action: :mark_no_show
      define :withdraw_before_start, action: :withdraw_before_start
      define :get_round_entry_by_id, action: :read, get_by: [:id]
    end
  end
end
