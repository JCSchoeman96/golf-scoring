defmodule GolfScoring.Competition.Changes.MarkReplacedBeforeStartInternal do
  @moduledoc false

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      entry = changeset.data

      case validate_transition(entry) do
        :ok ->
          Ash.Changeset.force_change_attribute(
            changeset,
            :registration_status,
            :replaced_before_start
          )

        {:error, message} ->
          Ash.Changeset.add_error(changeset, field: :registration_status, message: message)
      end
    end)
  end

  defp validate_transition(%{registration_status: status})
       when status in [:no_show, :withdrawn_before_start, :replaced_before_start] do
    {:error, "registration is terminal for this RoundEntry"}
  end

  defp validate_transition(%{participation_status: status}) when status != :not_started do
    {:error, "RoundEntry participation is already #{status}"}
  end

  defp validate_transition(%{registration_status: status})
       when status in [:expected, :checked_in],
       do: :ok

  defp validate_transition(_entry) do
    {:error, "RoundEntry cannot be marked replaced before start"}
  end
end
