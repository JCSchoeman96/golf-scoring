defmodule GolfScoringWeb.Admin.InputParsing do
  @moduledoc false

  alias Decimal, as: D

  @spec parse_uuid(term()) :: {:ok, Ecto.UUID.t()} | {:error, :invalid_input}
  def parse_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(String.trim(value)) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_input}
    end
  end

  def parse_uuid(_), do: {:error, :invalid_input}

  @spec parse_uuids(list()) :: {:ok, [Ecto.UUID.t()]} | {:error, :invalid_input}
  def parse_uuids(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case parse_uuid(value) do
        {:ok, uuid} -> {:cont, {:ok, [uuid | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, uuids} -> {:ok, Enum.reverse(uuids)}
      error -> error
    end
  end

  @spec parse_positive_integer(term()) :: {:ok, integer()} | {:error, :invalid_input}
  def parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  def parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int > 0 -> {:ok, int}
      _ -> {:error, :invalid_input}
    end
  end

  def parse_positive_integer(_), do: {:error, :invalid_input}

  @spec parse_optional_positive_integer(term()) ::
          {:ok, integer() | nil} | {:error, :invalid_input}
  def parse_optional_positive_integer(nil), do: {:ok, nil}
  def parse_optional_positive_integer(""), do: {:ok, nil}

  def parse_optional_positive_integer(value) do
    case parse_positive_integer(value) do
      {:ok, int} -> {:ok, int}
      {:error, :invalid_input} -> {:error, :invalid_input}
    end
  end

  @spec parse_decimal(term()) :: {:ok, Decimal.t()} | {:error, :invalid_input}
  def parse_decimal(%D{} = value), do: {:ok, value}

  def parse_decimal(value) when is_binary(value) do
    case D.parse(String.trim(value)) do
      {decimal, ""} -> {:ok, decimal}
      _ -> {:error, :invalid_input}
    end
  end

  def parse_decimal(_), do: {:error, :invalid_input}
end
