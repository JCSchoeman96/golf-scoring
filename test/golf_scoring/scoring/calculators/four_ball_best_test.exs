defmodule GolfScoring.Scoring.Calculators.FourBallBestTest do
  use ExUnit.Case, async: true

  alias GolfScoring.Scoring.Calculators.FourBallBest

  test "unequal partner points takes the higher value" do
    assert {:ok, %{best_points: 3}} = FourBallBest.calculate(3, 2)
    assert {:ok, %{best_points: 5}} = FourBallBest.calculate(5, 3)
  end

  test "equal partner points returns that value" do
    assert {:ok, %{best_points: 2}} = FourBallBest.calculate(2, 2)
  end

  test "both zero yields zero" do
    assert {:ok, %{best_points: 0}} = FourBallBest.calculate(0, 0)
  end

  test "valid value above four is not capped" do
    assert {:ok, %{best_points: 5}} = FourBallBest.calculate(5, 3)
    assert {:ok, %{best_points: 6}} = FourBallBest.calculate(4, 6)
  end

  test "rejects malformed, negative, and non-integer input" do
    assert {:error, :invalid_input} = FourBallBest.calculate(-1, 2)
    assert {:error, :invalid_input} = FourBallBest.calculate(2, -1)
    assert {:error, :invalid_input} = FourBallBest.calculate(1.5, 2)
    assert {:error, :invalid_input} = FourBallBest.calculate(2, 1.5)
    assert {:error, :invalid_input} = FourBallBest.calculate(nil, 2)
    assert {:error, :invalid_input} = FourBallBest.calculate(2, nil)
    assert {:error, :invalid_input} = FourBallBest.calculate("3", 2)
  end
end
