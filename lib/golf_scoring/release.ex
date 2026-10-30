defmodule GolfScoring.Release do
  @moduledoc false

  alias GolfScoring.Accounts.Services.BootstrapSystemAdmin
  alias GolfScoringWeb.Endpoint

  @app :golf_scoring
  @email_env "GOLF_SCORING_BOOTSTRAP_EMAIL"
  @password_env "GOLF_SCORING_BOOTSTRAP_PASSWORD"

  @doc "Creates or promotes the first active SYSTEM_ADMIN from a release eval."
  def bootstrap_system_admin do
    email = System.get_env(@email_env)
    password = System.get_env(@password_env)
    System.delete_env(@password_env)

    with {:ok, email} <- validate_email(email),
         :ok <- start_runtime_without_http_server() do
      case BootstrapSystemAdmin.bootstrap(email, password, %{"source" => "release_bootstrap"}) do
        {:ok, %{staff_user_id: id, mode: mode}} ->
          IO.puts("SYSTEM_ADMIN bootstrap completed: mode=#{mode} staff_user_id=#{id}")
          :ok

        {:error, reason} ->
          fail!(reason)
      end
    else
      {:error, reason} -> fail!(reason)
    end
  end

  defp validate_email(email) when is_binary(email) do
    if String.trim(email) == "", do: {:error, :email_required}, else: {:ok, email}
  end

  defp validate_email(_email), do: {:error, :email_required}

  defp start_runtime_without_http_server do
    case Application.ensure_loaded(@app) do
      :ok ->
        endpoint_config =
          @app
          |> Application.get_env(Endpoint, [])
          |> Keyword.put(:server, false)

        :ok = Application.put_env(@app, Endpoint, endpoint_config)

        case Application.ensure_all_started(@app) do
          {:ok, _started_apps} -> :ok
          {:error, _error} -> {:error, :runtime_start_failed}
        end

      {:error, _error} ->
        {:error, :runtime_start_failed}
    end
  rescue
    _error -> {:error, :runtime_start_failed}
  end

  defp fail!(reason) do
    message =
      case reason do
        :email_required -> "GOLF_SCORING_BOOTSTRAP_EMAIL is required"
        :password_required -> "bootstrap password is required for a new StaffUser"
        :inactive_target -> "target StaffUser is not active"
        :active_system_admin_exists -> "an active SYSTEM_ADMIN already exists"
        :provision_failed -> "StaffUser could not be provisioned"
        :audit_failed -> "bootstrap audit write failed"
        :runtime_start_failed -> "bootstrap runtime could not start"
        _reason -> "SYSTEM_ADMIN bootstrap failed"
      end

    raise RuntimeError, message: message
  end
end
