defmodule GolfScoring.Accounts.PlayerAccessExchange do
  @moduledoc false

  alias GolfScoring.Accounts.PlayerAccessGrantGuard
  alias GolfScoring.Accounts.PlayerAccessToken
  alias GolfScoring.Repo

  @spec exchange(String.t()) :: {:ok, map()} | {:error, :invalid_credentials}
  def exchange(token) when is_binary(token) and byte_size(token) > 0 do
    digest = PlayerAccessToken.digest(token)

    expiry_result =
      Repo.transaction(fn ->
        case PlayerAccessGrantGuard.apply_lazy_expiry_for_digest(Repo, digest) do
          :ok -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case expiry_result do
      {:ok, :ok} -> exchange_after_expiry(digest)
      _ -> {:error, :invalid_credentials}
    end
  end

  def exchange(_), do: {:error, :invalid_credentials}

  defp exchange_after_expiry(digest) do
    Repo.transaction(fn ->
      case PlayerAccessGrantGuard.find_usable_active_by_digest(Repo, digest) do
        {:ok, grant} -> grant
        {:error, :invalid_credentials} -> Repo.rollback(:invalid_credentials)
      end
    end)
    |> case do
      {:ok, grant} -> {:ok, grant}
      {:error, :invalid_credentials} -> {:error, :invalid_credentials}
      {:error, :rollback, :invalid_credentials} -> {:error, :invalid_credentials}
      {:error, _} -> {:error, :invalid_credentials}
    end
  end
end
