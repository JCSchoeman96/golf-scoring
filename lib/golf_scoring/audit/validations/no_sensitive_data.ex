defmodule GolfScoring.Audit.Validations.NoSensitiveData do
  @moduledoc false

  use Ash.Resource.Validation

  @sensitive_keys MapSet.new(["password", "passwordconfirmation", "hashedpassword"])

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    case Enum.find([:context, :changes], fn field ->
           contains_sensitive_key?(Ash.Changeset.get_attribute(changeset, field))
         end) do
      nil ->
        :ok

      field ->
        {:error, field: field, message: "must not contain credential fields"}
    end
  end

  defp contains_sensitive_key?(value) when is_map(value) do
    Enum.any?(value, fn {key, nested_value} ->
      sensitive_key?(key) or contains_sensitive_key?(nested_value)
    end)
  end

  defp contains_sensitive_key?(value) when is_list(value) do
    Enum.any?(value, &contains_sensitive_key?/1)
  end

  defp contains_sensitive_key?(_value), do: false

  defp sensitive_key?(key) when is_atom(key) or is_binary(key) do
    key
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/, "")
    |> then(&MapSet.member?(@sensitive_keys, &1))
  end

  defp sensitive_key?(_key), do: false
end
