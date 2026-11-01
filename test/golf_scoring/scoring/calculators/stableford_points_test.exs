defmodule GolfScoring.Scoring.Calculators.StablefordPointsTest do
  use ExUnit.Case, async: true

  alias GolfScoring.Scoring.Calculators.StablefordPoints

  defp holed(gross, par, allocated_strokes) do
    StablefordPoints.calculate(%{
      outcome: :holed_out,
      gross_strokes: gross,
      par: par,
      allocated_strokes: allocated_strokes
    })
  end

  test "net bogey on scratch par 4 awards 1 point" do
    assert {:ok, %{competition_points: 1, competition_net_strokes: 5, gross_strokes: 5}} =
             holed(5, 4, 0)
  end

  test "net par on scratch par 4 awards 2 points" do
    assert {:ok, %{competition_points: 2, competition_net_strokes: 4, gross_strokes: 4}} =
             holed(4, 4, 0)
  end

  test "net birdie on scratch par 4 awards 3 points" do
    assert {:ok, %{competition_points: 3, competition_net_strokes: 3, gross_strokes: 3}} =
             holed(3, 4, 0)
  end

  test "net eagle on scratch par 4 awards 4 points" do
    assert {:ok, %{competition_points: 4, competition_net_strokes: 2, gross_strokes: 2}} =
             holed(2, 4, 0)
  end

  test "worse than net bogey awards 0 points" do
    assert {:ok, %{competition_points: 0, competition_net_strokes: 6, gross_strokes: 6}} =
             holed(6, 4, 0)
  end

  test "one received stroke shifts net result and points" do
    assert {:ok, %{competition_points: 2, competition_net_strokes: 4, gross_strokes: 5}} =
             holed(5, 4, 1)
  end

  test "plus give-back stroke shifts net result and points" do
    assert {:ok, %{competition_points: 2, competition_net_strokes: 4, gross_strokes: 3}} =
             holed(3, 4, -1)
  end

  test "very high actual gross is preserved and yields 0 competition points" do
    assert {:ok, %{competition_points: 0, competition_net_strokes: 11, gross_strokes: 11}} =
             holed(11, 4, 0)
  end

  test "holed_out without gross strokes does not fabricate a score" do
    assert {:error, :invalid_outcome_gross_combination} =
             StablefordPoints.calculate(%{
               outcome: :holed_out,
               gross_strokes: nil,
               par: 4,
               allocated_strokes: 0
             })
  end

  test "picked_up has nil gross and 0 competition points" do
    assert {:ok, %{competition_points: 0, gross_strokes: nil}} =
             StablefordPoints.calculate(%{
               outcome: :picked_up,
               gross_strokes: nil,
               par: 4,
               allocated_strokes: 0
             })
  end

  test "picked_up does not invent a gross score when gross is absent" do
    assert {:ok, result} =
             StablefordPoints.calculate(%{
               outcome: :picked_up,
               par: 4,
               allocated_strokes: 1
             })

    assert result.competition_points == 0
    assert result.gross_strokes == nil
    refute Map.has_key?(result, :competition_net_strokes)
  end
end
