defmodule GolfScoring.Scoring.Calculators.SoloNormalizationTest do
  use ExUnit.Case, async: true

  alias GolfScoring.Scoring.Calculators.SoloNormalization

  test "P=0 yields [0, 0]" do
    assert {:ok,
            %{
              player_points: 0,
              companion_points: 0,
              normalized_contributors: [0, 0]
            }} = SoloNormalization.normalize(0)
  end

  test "P=1 yields [1, 0]" do
    assert {:ok,
            %{
              player_points: 1,
              companion_points: 0,
              normalized_contributors: [1, 0]
            }} = SoloNormalization.normalize(1)
  end

  test "P=2 yields [2, 1]" do
    assert {:ok,
            %{
              player_points: 2,
              companion_points: 1,
              normalized_contributors: [2, 1]
            }} = SoloNormalization.normalize(2)
  end

  test "P=3 yields [3, 2]" do
    assert {:ok,
            %{
              player_points: 3,
              companion_points: 2,
              normalized_contributors: [3, 2]
            }} = SoloNormalization.normalize(3)
  end

  test "P=4 yields [4, 3]" do
    assert {:ok,
            %{
              player_points: 4,
              companion_points: 3,
              normalized_contributors: [4, 3]
            }} = SoloNormalization.normalize(4)
  end

  test "P above four is not capped" do
    assert {:ok,
            %{
              player_points: 5,
              companion_points: 4,
              normalized_contributors: [5, 4]
            }} = SoloNormalization.normalize(5)
  end

  test "rejects malformed, negative, and non-integer input" do
    assert {:error, :invalid_input} = SoloNormalization.normalize(-1)
    assert {:error, :invalid_input} = SoloNormalization.normalize(1.5)
    assert {:error, :invalid_input} = SoloNormalization.normalize(nil)
    assert {:error, :invalid_input} = SoloNormalization.normalize("2")
  end
end
