defmodule GolfScoring.Accounts.Services.ProvisionStaffUser do
  @moduledoc "Coordinates ordinary SYSTEM_ADMIN staff provisioning."

  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Accounts.SystemAdminGuard
  alias GolfScoring.Audit
  alias GolfScoring.Repo

  @type safe_reason :: :forbidden | :email_already_exists | :invalid_credentials | :audit_failed

  @spec provision(term(), map()) :: {:ok, StaffUser.t()} | {:error, safe_reason()}
  def provision(actor, attributes) when is_map(attributes) do
    with :ok <- valid_attributes(attributes) do
      provision_transaction(actor, attributes)
    end
  end

  def provision(_actor, _attributes), do: {:error, :invalid_credentials}

  defp valid_attributes(
         %{
           email: email,
           password: password,
           password_confirmation: password_confirmation
         } = attributes
       )
       when map_size(attributes) == 3 and is_binary(email) and is_binary(password) and
              is_binary(password_confirmation) do
    if String.trim(email) == "" do
      {:error, :invalid_credentials}
    else
      :ok
    end
  end

  defp valid_attributes(_attributes), do: {:error, :invalid_credentials}

  defp provision_transaction(actor, attributes) do
    transaction_result =
      try do
        Repo.transaction(fn ->
          :ok = SystemAdminGuard.acquire_lock!()

          with {:ok, actor_row} <- lock_active_actor(actor),
               :ok <- email_available(attributes.email),
               {:ok, user} <- create_staff_user(attributes),
               :ok <- record_provision_audit(actor_row, user) do
            user
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
      rescue
        _error -> {:error, :provision_failed}
      catch
        _kind, _reason -> {:error, :provision_failed}
      end

    case transaction_result do
      {:ok, user} -> {:ok, user}
      {:error, :forbidden} -> {:error, :forbidden}
      {:error, :email_already_exists} -> {:error, :email_already_exists}
      {:error, :invalid_credentials} -> {:error, :invalid_credentials}
      {:error, :audit_failed} -> {:error, :audit_failed}
      {:error, %Ash.Changeset{}} -> {:error, :audit_failed}
      _other -> {:error, :invalid_credentials}
    end
  end

  defp lock_active_actor(actor) do
    case actor_id(actor) do
      nil ->
        {:error, :forbidden}

      id ->
        case Repo.query!(
               """
               SELECT id::text, status, system_admin
               FROM staff_users
               WHERE id = $1::uuid
               FOR UPDATE
               """,
               [Ecto.UUID.dump!(id)]
             ).rows do
          [[row_id, "active", true]] -> {:ok, %{id: Ecto.UUID.cast!(row_id)}}
          _rows -> {:error, :forbidden}
        end
    end
  end

  defp actor_id(actor) when is_map(actor) do
    case Ecto.UUID.cast(Map.get(actor, :id)) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp actor_id(_actor), do: nil

  defp email_available(email) do
    case Repo.query!("SELECT 1 FROM staff_users WHERE email = $1::citext LIMIT 1", [email]).rows do
      [] -> :ok
      [[1]] -> {:error, :email_already_exists}
    end
  end

  defp create_staff_user(attributes) do
    changeset = Ash.Changeset.for_create(StaffUser, :provision_staff_user, attributes)

    case with_sensitive_query_logs_suppressed(fn ->
           Ash.create(changeset, authorize?: false, return_notifications?: true)
         end) do
      {:ok, user, _notifications} -> {:ok, user}
      {:ok, user} -> {:ok, user}
      {:error, _error} -> {:error, :invalid_credentials}
    end
  rescue
    _error -> {:error, :invalid_credentials}
  end

  defp with_sensitive_query_logs_suppressed(fun) do
    previous_level = Logger.get_process_level(self())
    :ok = Logger.put_process_level(self(), :none)

    try do
      fun.()
    after
      case previous_level do
        nil -> Logger.delete_process_level(self())
        level -> Logger.put_process_level(self(), level)
      end
    end
  end

  defp record_provision_audit(actor, user) do
    attributes = %{
      actor_staff_user_id: actor.id,
      action: "staff_user_provisioned",
      target_type: "staff_user",
      target_id: user.id,
      changes: %{"status" => %{"from" => nil, "to" => "active"}}
    }

    case Audit.record_staff_event(attributes, authorize?: false, return_notifications?: true) do
      {:ok, _event, _notifications} -> :ok
      {:ok, _event} -> :ok
      {:error, _error} -> {:error, :audit_failed}
    end
  rescue
    _error -> {:error, :audit_failed}
  end
end
