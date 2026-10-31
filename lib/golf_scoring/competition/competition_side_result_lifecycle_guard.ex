defmodule GolfScoring.Competition.CompetitionSideResultLifecycleGuard do
  @moduledoc false

  use Ash.Resource.Change

  @future_dependency_message "cannot transition CompetitionSideResult until required scoring, verification and readiness evidence is implemented"

  @impl true
  def change(changeset, opts, _context) do
    operation = Keyword.fetch!(opts, :operation)

    Ash.Changeset.before_action(changeset, fn changeset ->
      Ash.Changeset.add_error(changeset, field: :state, message: transition_message(operation))
    end)
  end

  defp transition_message(:mark_review_required),
    do: "#{@future_dependency_message} for mark_review_required"

  defp transition_message(:mark_ready_to_finalize),
    do: "#{@future_dependency_message} for mark_ready_to_finalize"

  defp transition_message(:finalize), do: "#{@future_dependency_message} for finalize"
  defp transition_message(:reopen), do: "#{@future_dependency_message} for reopen"
  defp transition_message(:exclude), do: "#{@future_dependency_message} for exclude"
end
