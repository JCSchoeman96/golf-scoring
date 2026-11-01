defmodule GolfScoring.Accounts.PlayerAccessToken do
  @moduledoc false

  @entropy_bytes 32

  @spec generate() :: {String.t(), binary()}
  def generate do
    bytes = :crypto.strong_rand_bytes(@entropy_bytes)
    token = Base.url_encode64(bytes, padding: false)
    {token, digest(token)}
  end

  @spec digest(String.t()) :: binary()
  def digest(token) when is_binary(token) do
    :crypto.hash(:sha256, token)
  end
end
