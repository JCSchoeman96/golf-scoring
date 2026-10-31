defmodule GolfScoring.Competition.PlayingGroupLifecycleGuard do
  @moduledoc false

  use Ash.Resource.Change

  @future_dependency_message "cannot transition PlayingGroup lifecycle until required HoleSubmission and completion evidence is implemented"

  @impl true
  def change(changeset, opts, _context) do
    operation = Keyword.fetch!(opts, :operation)

    Ash.Changeset.before_action(changeset, fn changeset ->
      Ash.Changeset.add_error(changeset, field: :state, message: transition_message(operation))
    end)
  end

  defp transition_message(:mark_group_playing),
    do: "#{@future_dependency_message} for mark_group_playing"

  defp transition_message(:mark_group_finished),
    do: "#{@future_dependency_message} for mark_group_finished"

  defp transition_message(:flag_group_attention),
    do: "#{@future_dependency_message} for flag_group_attention"

  defp transition_message(:clear_group_attention),
    do: "#{@future_dependency_message} for clear_group_attention"
end
