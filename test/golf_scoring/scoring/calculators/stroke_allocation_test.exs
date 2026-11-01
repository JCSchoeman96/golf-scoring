defmodule GolfScoring.Scoring.Calculators.StrokeAllocationTest do
  use ExUnit.Case, async: true

  alias GolfScoring.Scoring.Calculators.StrokeAllocation

  defp hole(stroke_index, opts \\ []) do
    id = Keyword.get(opts, :round_hole_id, "hole-#{stroke_index}")

    %{
      round_hole_id: id,
      stroke_index: stroke_index,
      plus_stroke_order: Keyword.get(opts, :plus_stroke_order)
    }
  end

  defp standard_holes do
    for si <- 1..18, do: hole(si)
  end

  defp plus_holes_with_sa_sequence do
    # Deliberately place plus_stroke_order 1 on stroke index 10 (not SI 1).
    plus_by_si = %{
      10 => 1,
      3 => 2,
      14 => 3,
      7 => 4,
      18 => 5,
      2 => 6,
      11 => 7,
      5 => 8
    }

    for si <- 1..18 do
      hole(si, plus_stroke_order: Map.get(plus_by_si, si))
    end
  end

  defp strokes_for(holes, playing_handicap) do
    {:ok, %{strokes_by_round_hole_id: strokes}} =
      StrokeAllocation.allocate(playing_handicap, holes)

    strokes
  end

  test "playing handicap 0 allocates zero strokes on every hole" do
    strokes = strokes_for(standard_holes(), 0)

    assert map_size(strokes) == 18
    assert Enum.all?(Map.values(strokes), &(&1 == 0))
  end

  test "playing handicap 1 gives one stroke on stroke index 1" do
    strokes = strokes_for(standard_holes(), 1)

    assert strokes["hole-1"] == 1

    assert Enum.all?(2..18, fn si ->
             strokes["hole-#{si}"] == 0
           end)
  end

  test "playing handicap 18 gives one stroke on every hole" do
    strokes = strokes_for(standard_holes(), 18)
    assert Enum.all?(Map.values(strokes), &(&1 == 1))
  end

  test "playing handicap 19 gives two strokes on stroke index 1" do
    strokes = strokes_for(standard_holes(), 19)

    assert strokes["hole-1"] == 2

    assert Enum.all?(2..18, fn si ->
             strokes["hole-#{si}"] == 1
           end)
  end

  test "playing handicap 36 gives two strokes on every hole" do
    strokes = strokes_for(standard_holes(), 36)
    assert Enum.all?(Map.values(strokes), &(&1 == 2))
  end

  test "playing handicap 37 gives three strokes on stroke index 1 only" do
    strokes = strokes_for(standard_holes(), 37)

    assert strokes["hole-1"] == 3

    assert Enum.all?(2..18, fn si ->
             strokes["hole-#{si}"] == 2
           end)
  end

  test "plus playing handicap -1 uses plus_stroke_order not stroke index" do
    holes = plus_holes_with_sa_sequence()
    strokes = strokes_for(holes, -1)

    assert strokes["hole-10"] == -1
    assert strokes["hole-1"] == 0
  end

  test "plus playing handicap -8 gives back on all eight plus stroke orders" do
    holes = plus_holes_with_sa_sequence()
    strokes = strokes_for(holes, -8)

    assert strokes["hole-10"] == -1
    assert strokes["hole-3"] == -1
    assert strokes["hole-14"] == -1
    assert strokes["hole-7"] == -1
    assert strokes["hole-18"] == -1
    assert strokes["hole-2"] == -1
    assert strokes["hole-11"] == -1
    assert strokes["hole-5"] == -1

    assert strokes["hole-1"] == 0
    assert strokes["hole-17"] == 0
  end

  test "plus playing handicap below -8 is rejected" do
    holes = plus_holes_with_sa_sequence()

    assert {:error, :plus_playing_handicap_outside_authorized_range} =
             StrokeAllocation.allocate(-9, holes)
  end

  test "plus playing handicap rejects missing plus stroke allocation" do
    assert {:error, :invalid_plus_stroke_allocation} =
             StrokeAllocation.allocate(-1, standard_holes())
  end

  test "plus playing handicap rejects invalid plus stroke allocation" do
    holes =
      for si <- 1..18 do
        order = if si <= 7, do: si, else: nil
        hole(si, plus_stroke_order: order)
      end

    assert {:error, :invalid_plus_stroke_allocation} =
             StrokeAllocation.allocate(-1, holes)
  end

  test "malformed hole sets are rejected" do
    too_few = Enum.take(standard_holes(), 17)

    assert {:error, :invalid_hole_set} = StrokeAllocation.allocate(5, too_few)

    duplicate_si =
      standard_holes()
      |> List.replace_at(0, hole(1, round_hole_id: "dup-a"))
      |> List.replace_at(1, hole(1, round_hole_id: "dup-b"))

    assert {:error, :invalid_hole_set} = StrokeAllocation.allocate(5, duplicate_si)
  end

  test "missing round_hole_id returns invalid_hole_set" do
    holes =
      standard_holes()
      |> List.update_at(0, fn %{stroke_index: si, plus_stroke_order: pso} ->
        %{stroke_index: si, plus_stroke_order: pso}
      end)

    assert {:error, :invalid_hole_set} = StrokeAllocation.allocate(5, holes)
  end

  test "nil round_hole_id returns invalid_hole_set" do
    holes = List.replace_at(standard_holes(), 0, hole(1, round_hole_id: nil))

    assert {:error, :invalid_hole_set} = StrokeAllocation.allocate(5, holes)
  end

  test "missing stroke_index returns invalid_hole_set" do
    holes =
      standard_holes()
      |> List.update_at(0, fn %{round_hole_id: id, plus_stroke_order: pso} ->
        %{round_hole_id: id, plus_stroke_order: pso}
      end)

    assert {:error, :invalid_hole_set} = StrokeAllocation.allocate(5, holes)
  end

  test "duplicate round_hole_id returns invalid_hole_set" do
    holes =
      standard_holes()
      |> List.replace_at(17, hole(18, round_hole_id: "hole-1"))

    assert {:error, :invalid_hole_set} = StrokeAllocation.allocate(5, holes)
  end
end
