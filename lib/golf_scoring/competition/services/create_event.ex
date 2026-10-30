defmodule GolfScoring.Competition.Services.CreateEvent do
  @moduledoc false

  alias GolfScoring.Accounts.EventStaffAssignment
  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Audit
  alias GolfScoring.Competition.Event
  alias GolfScoring.Repo

  @type result :: %{event: Event.t()}

  @doc false
  @spec create(StaffUser.t(), map()) :: {:ok, result()} | {:error, atom()}
  def create(%StaffUser{} = actor, safe_context) when is_map(safe_context) do
    case authorize(actor) do
      :ok -> run_transaction(actor, safe_context)
      {:error, reason} -> {:error, reason}
    end
  end

  def create(_actor, _safe_context), do: {:error, :forbidden}

  defp authorize(%StaffUser{status: :active, system_admin: true}), do: :ok
  defp authorize(_), do: {:error, :forbidden}

  defp run_transaction(actor, safe_context) do
    transaction_result =
      try do
        Repo.transaction(fn ->
          with {:ok, event} <- create_event(),
               {:ok, _assignment} <- create_initial_assignment(event, actor),
               :ok <- record_audit(event, actor, safe_context) do
            %{event: event}
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
      rescue
        _error -> {:error, :create_event_failed}
      catch
        _kind, _reason -> {:error, :create_event_failed}
      end

    case transaction_result do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, safe_reason(reason)}
      _other -> {:error, :create_event_failed}
    end
  end

  defp create_event do
    case Event
         |> Ash.Changeset.for_create(:create_internal, %{})
         |> Ash.create(authorize?: false) do
      {:ok, event} -> {:ok, event}
      {:error, _error} -> {:error, :event_create_failed}
    end
  end

  defp create_initial_assignment(event, actor) do
    case EventStaffAssignment
         |> Ash.Changeset.for_create(:create_initial_event_admin_internal, %{
           event_id: event.id,
           staff_user_id: actor.id
         })
         |> Ash.create(authorize?: false) do
      {:ok, assignment} -> {:ok, assignment}
      {:error, _error} -> {:error, :assignment_failed}
    end
  end

  defp record_audit(event, actor, safe_context) do
    attributes = %{
      actor_staff_user_id: actor.id,
      action: "event_created",
      target_type: "event",
      target_id: event.id,
      context:
        safe_context
        |> Map.new(fn {k, v} -> {to_string(k), v} end)
        |> Map.put("initial_event_admin_staff_user_id", actor.id),
      changes: %{"state" => %{"from" => nil, "to" => "draft"}}
    }

    case Audit.record_staff_event(attributes, authorize?: false, return_notifications?: true) do
      {:ok, _event, _notifications} -> :ok
      {:ok, _event} -> :ok
      {:error, _error} -> {:error, :audit_failed}
    end
  rescue
    _error -> {:error, :audit_failed}
  end

  defp safe_reason(reason)
       when reason in [:event_create_failed, :assignment_failed, :audit_failed],
       do: reason

  defp safe_reason(_reason), do: :create_event_failed
end
