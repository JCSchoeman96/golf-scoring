defmodule GolfScoring.Scoring.Calculators.MysteryAggregationTest do
  use ExUnit.Case, async: true

  alias GolfScoring.Scoring.Calculators.MysteryAggregation

  test "[4, 2] with :best returns 4" do
    assert {:ok, %{mystery_points: 4}} = MysteryAggregation.calculate([4, 2], :best)
  end

  test "[4, 2] with :worst returns 2" do
    assert {:ok, %{mystery_points: 2}} = MysteryAggregation.calculate([4, 2], :worst)
  end

  test "[4, 2] with :both returns 6" do
    assert {:ok, %{mystery_points: 6}} = MysteryAggregation.calculate([4, 2], :both)
  end

  test "[3, 3] ties for best and worst" do
    assert {:ok, %{mystery_points: 3}} = MysteryAggregation.calculate([3, 3], :best)
    assert {:ok, %{mystery_points: 3}} = MysteryAggregation.calculate([3, 3], :worst)
    assert {:ok, %{mystery_points: 6}} = MysteryAggregation.calculate([3, 3], :both)
  end

  test "[0, 0] zero contributions" do
    assert {:ok, %{mystery_points: 0}} = MysteryAggregation.calculate([0, 0], :best)
    assert {:ok, %{mystery_points: 0}} = MysteryAggregation.calculate([0, 0], :worst)
    assert {:ok, %{mystery_points: 0}} = MysteryAggregation.calculate([0, 0], :both)
  end

  test "accepted normalized solo [3, 2]" do
    assert {:ok, %{mystery_points: 3}} = MysteryAggregation.calculate([3, 2], :best)
    assert {:ok, %{mystery_points: 2}} = MysteryAggregation.calculate([3, 2], :worst)
    assert {:ok, %{mystery_points: 5}} = MysteryAggregation.calculate([3, 2], :both)
  end

  test "accepted normalized solo [0, 0]" do
    assert {:ok, %{mystery_points: 0}} = MysteryAggregation.calculate([0, 0], :best)
    assert {:ok, %{mystery_points: 0}} = MysteryAggregation.calculate([0, 0], :worst)
    assert {:ok, %{mystery_points: 0}} = MysteryAggregation.calculate([0, 0], :both)
  end

  test "above-four values are not capped" do
    assert {:ok, %{mystery_points: 6}} = MysteryAggregation.calculate([6, 5], :best)
    assert {:ok, %{mystery_points: 5}} = MysteryAggregation.calculate([6, 5], :worst)
    assert {:ok, %{mystery_points: 11}} = MysteryAggregation.calculate([6, 5], :both)
  end

  test "empty contributions returns :no_contributions" do
    assert {:error, :no_contributions} = MysteryAggregation.calculate([], :best)
  end

  test "unknown rule returns :unsupported_rule" do
    assert {:error, :unsupported_rule} = MysteryAggregation.calculate([4, 2], :unknown)
    assert {:error, :unsupported_rule} = MysteryAggregation.calculate([4, 2], "best")
  end

  test "invalid contribution inputs return :invalid_input" do
    assert {:error, :invalid_input} = MysteryAggregation.calculate([-1, 2], :best)
    assert {:error, :invalid_input} = MysteryAggregation.calculate([1.5, 2], :best)
    assert {:error, :invalid_input} = MysteryAggregation.calculate([nil, 2], :best)
    assert {:error, :invalid_input} = MysteryAggregation.calculate(["4", 2], :best)
    assert {:error, :invalid_input} = MysteryAggregation.calculate(123, :best)
    assert {:error, :invalid_input} = MysteryAggregation.calculate(nil, :best)
  end
end
