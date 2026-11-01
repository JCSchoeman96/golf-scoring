defmodule GolfScoring.Scoring.Calculators.StrokeAllocation do
  @moduledoc """
  Pure per-hole stroke allocation from playing handicap and frozen hole facts.
  """

  @expected_hole_count 18
  @expected_stroke_indices 1..18
  @expected_plus_orders 1..8

  @doc """
  Allocates signed strokes per `round_hole_id`.

  Returns `{:ok, %{strokes_by_round_hole_id: %{uuid => integer}}}`.
  """
  @spec allocate(integer(), list(map())) ::
          {:ok, %{strokes_by_round_hole_id: map()}} | {:error, atom()}
  def allocate(playing_handicap, holes) when is_list(holes) do
    with :ok <- validate_holes(holes),
         {:ok, strokes_by_round_hole_id} <- allocate_strokes(playing_handicap, holes) do
      {:ok, %{strokes_by_round_hole_id: strokes_by_round_hole_id}}
    end
  end

  defp allocate_strokes(playing_handicap, holes) do
    cond do
      playing_handicap > 0 ->
        {:ok, allocate_positive(playing_handicap, holes)}

      playing_handicap == 0 ->
        {:ok, zero_map(holes)}

      playing_handicap >= -8 and playing_handicap <= -1 ->
        with :ok <- validate_plus_stroke_allocation(holes) do
          {:ok, allocate_plus(playing_handicap, holes)}
        end

      playing_handicap < -8 ->
        {:error, :plus_playing_handicap_outside_authorized_range}
    end
  end

  defp validate_holes(holes) do
    cond do
      length(holes) != @expected_hole_count ->
        {:error, :invalid_hole_set}

      not Enum.all?(holes, &hole_fact_valid?/1) ->
        {:error, :invalid_hole_set}

      length(unique_round_hole_ids(holes)) != @expected_hole_count ->
        {:error, :invalid_hole_set}

      MapSet.new(stroke_indices(holes)) != MapSet.new(@expected_stroke_indices) ->
        {:error, :invalid_hole_set}

      true ->
        :ok
    end
  end

  defp hole_fact_valid?(hole) do
    case {Map.get(hole, :round_hole_id), Map.get(hole, :stroke_index)} do
      {round_hole_id, stroke_index}
      when not is_nil(round_hole_id) and is_integer(stroke_index) ->
        true

      _ ->
        false
    end
  end

  defp unique_round_hole_ids(holes) do
    holes
    |> Enum.map(&Map.get(&1, :round_hole_id))
    |> Enum.uniq()
  end

  defp stroke_indices(holes) do
    Enum.map(holes, &Map.get(&1, :stroke_index))
  end

  defp validate_plus_stroke_allocation(holes) do
    orders =
      holes
      |> Enum.map(&Map.get(&1, :plus_stroke_order))
      |> Enum.reject(&is_nil/1)

    expected = MapSet.new(@expected_plus_orders)

    cond do
      MapSet.new(orders) != expected ->
        {:error, :invalid_plus_stroke_allocation}

      length(orders) != 8 ->
        {:error, :invalid_plus_stroke_allocation}

      Enum.any?(orders, &(not is_integer(&1) or &1 not in @expected_plus_orders)) ->
        {:error, :invalid_plus_stroke_allocation}

      true ->
        :ok
    end
  end

  defp allocate_positive(playing_handicap, holes) do
    base = div(playing_handicap, @expected_hole_count)
    extra = rem(playing_handicap, @expected_hole_count)

    Map.new(holes, fn hole ->
      stroke_index = Map.fetch!(hole, :stroke_index)
      strokes = base + if(stroke_index <= extra, do: 1, else: 0)
      {Map.fetch!(hole, :round_hole_id), strokes}
    end)
  end

  defp allocate_plus(playing_handicap, holes) do
    give_back_count = abs(playing_handicap)

    Map.new(holes, fn hole ->
      order = Map.get(hole, :plus_stroke_order)

      strokes =
        if is_integer(order) and order <= give_back_count do
          -1
        else
          0
        end

      {Map.fetch!(hole, :round_hole_id), strokes}
    end)
  end

  defp zero_map(holes) do
    Map.new(holes, fn hole -> {Map.fetch!(hole, :round_hole_id), 0} end)
  end
end
