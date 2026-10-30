defmodule GolfScoring.Accounts.Services.BootstrapSystemAdmin do
  @moduledoc false

  alias GolfScoring.Accounts.StaffUser
  alias GolfScoring.Accounts.SystemAdminGuard
  alias GolfScoring.Audit
  alias GolfScoring.Repo

  require Ash.Query

  @type mode :: :created | :promoted
  @type result :: %{staff_user_id: Ecto.UUID.t(), mode: mode()}

  @doc false
  @spec bootstrap(String.t(), String.t() | nil, map()) ::
          {:ok, result()} | {:error, atom()}
  def bootstrap(email, password, safe_context)
      when is_binary(email) and is_map(safe_context) do
    if String.trim(email) == "" do
      {:error, :email_required}
    else
      run_transaction(email, password, safe_context)
    end
  end

  def bootstrap(_email, _password, _safe_context), do: {:error, :email_required}

  defp run_transaction(email, password, safe_context) do
    transaction_result =
      try do
        Repo.transaction(fn ->
          :ok = SystemAdminGuard.acquire_lock!()

          case bootstrap_locked(email, password, safe_context) do
            {:ok, result} -> result
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
      rescue
        _error -> {:error, :bootstrap_failed}
      catch
        _kind, _reason -> {:error, :bootstrap_failed}
      end

    case transaction_result do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, safe_reason(reason)}
      _other -> {:error, :bootstrap_failed}
    end
  end

  defp bootstrap_locked(email, password, safe_context) do
    with :ok <- ensure_no_active_system_admin(),
         {:ok, target} <- find_target(email),
         {:ok, user, mode} <- create_or_promote(target, email, password),
         :ok <- record_bootstrap_audit(user, mode, safe_context) do
      {:ok, %{staff_user_id: user.id, mode: mode}}
    end
  end

  defp ensure_no_active_system_admin do
    case Repo.query!(
           "SELECT count(*) FROM staff_users WHERE status = 'active' AND system_admin = TRUE"
         ).rows do
      [[0]] -> :ok
      [[count]] when count > 0 -> {:error, :active_system_admin_exists}
    end
  end

  defp find_target(email) do
    StaffUser
    |> Ash.Query.filter(email: email)
    |> Ash.read_one(authorize?: false)
  rescue
    _error -> {:error, :bootstrap_failed}
  end

  defp create_or_promote(nil, _email, nil), do: {:error, :password_required}

  defp create_or_promote(nil, email, password) when is_binary(password) do
    attributes = %{
      email: email,
      password: password,
      password_confirmation: password
    }

    changeset = Ash.Changeset.for_create(StaffUser, :provision_staff_user, attributes)

    case with_sensitive_query_logs_suppressed(fn ->
           Ash.create(changeset, authorize?: false, return_notifications?: true)
         end) do
      {:ok, user, _notifications} -> promote(user, :created)
      {:error, _error} -> {:error, :provision_failed}
    end
  rescue
    _error -> {:error, :provision_failed}
  end

  defp create_or_promote(nil, _email, _password), do: {:error, :password_required}

  defp create_or_promote(target, _email, _password) do
    with :ok <- lock_target(target.id),
         {:ok, current_target} <- reload_target(target.id),
         :ok <- eligible_target(current_target) do
      promote(current_target, :promoted)
    end
  end

  defp with_sensitive_query_logs_suppressed(fun) do
    # Ecto SQL debug output includes bind parameters, including the generated password hash.
    previous_level = Logger.get_process_level(self())
    :ok = Logger.put_process_level(self(), :none)

    try do
      fun.()
    after
      :ok = Logger.put_process_level(self(), previous_level || :all)
    end
  end

  defp lock_target(id) do
    case Repo.query!(
           "SELECT id FROM staff_users WHERE id = $1::uuid FOR UPDATE",
           [Ecto.UUID.dump!(id)]
         ).rows do
      [[_id]] -> :ok
      [] -> {:error, :target_not_found}
    end
  rescue
    _error -> {:error, :bootstrap_failed}
  end

  defp reload_target(id) do
    StaffUser
    |> Ash.Query.filter(id: id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :target_not_found}
      {:ok, user} -> {:ok, user}
      {:error, _error} -> {:error, :bootstrap_failed}
    end
  rescue
    _error -> {:error, :bootstrap_failed}
  end

  defp eligible_target(%{status: :active, system_admin: false}), do: :ok
  defp eligible_target(%{status: status}) when status != :active, do: {:error, :inactive_target}
  defp eligible_target(%{system_admin: true}), do: {:error, :active_system_admin_exists}
  defp eligible_target(_target), do: {:error, :target_not_eligible}

  defp promote(user, mode) do
    case Ash.update(user, %{},
           action: :bootstrap_system_admin,
           authorize?: false,
           return_notifications?: true
         ) do
      {:ok, promoted_user, _notifications} -> {:ok, promoted_user, mode}
      {:ok, promoted_user} -> {:ok, promoted_user, mode}
      {:error, _error} -> {:error, :bootstrap_failed}
    end
  rescue
    _error -> {:error, :bootstrap_failed}
  end

  defp record_bootstrap_audit(user, mode, safe_context) do
    attributes = %{
      action: "system_admin_bootstrapped",
      target_type: "staff_user",
      target_id: user.id,
      context: Map.put(safe_context, "mode", Atom.to_string(mode)),
      changes: %{"system_admin" => %{"from" => false, "to" => true}}
    }

    case Audit.record_system_event(attributes, authorize?: false, return_notifications?: true) do
      {:ok, _event, _notifications} -> :ok
      {:ok, _event} -> :ok
      {:error, _error} -> {:error, :audit_failed}
    end
  rescue
    _error -> {:error, :audit_failed}
  end

  defp safe_reason(reason)
       when reason in [
              :active_system_admin_exists,
              :inactive_target,
              :password_required,
              :target_not_found,
              :target_not_eligible,
              :audit_failed,
              :provision_failed
            ],
       do: reason

  defp safe_reason(_reason), do: :bootstrap_failed
end
