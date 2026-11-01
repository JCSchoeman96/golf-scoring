defmodule GolfScoring.Scoring.Calculators.PlayingHandicapTest do
  use ExUnit.Case, async: true

  alias Decimal, as: D
  alias GolfScoring.Scoring.Calculators.CourseHandicap
  alias GolfScoring.Scoring.Calculators.PlayingHandicap

  defp course_handicap_unrounded!(handicap_index) do
    {:ok, %{course_handicap_unrounded: unrounded}} =
      CourseHandicap.calculate(handicap_index, 125, D.new("71.0"), 71)

    unrounded
  end

  test "SA 2026 player A: HI 8.6 allowance 85% playing handicap 8" do
    unrounded = course_handicap_unrounded!(D.new("8.6"))

    assert D.equal?(D.round(unrounded, 4), D.new("9.5133"))

    assert {:ok, result} = PlayingHandicap.calculate(unrounded, 85)
    assert result.playing_handicap == 8
    refute D.equal?(result.unrounded_allowed_handicap, D.new("8"))
  end

  test "SA 2026 player B: HI 10.3 allowance 85% playing handicap 10" do
    unrounded = course_handicap_unrounded!(D.new("10.3"))

    assert D.equal?(D.round(unrounded, 4), D.new("11.3938"))

    assert {:ok, result} = PlayingHandicap.calculate(unrounded, 85)
    assert result.playing_handicap == 10
  end

  test "100% allowance keeps unrounded course handicap intermediate" do
    unrounded = course_handicap_unrounded!(D.new("8.6"))

    assert {:ok, result} = PlayingHandicap.calculate(unrounded, 100)

    assert D.equal?(result.unrounded_allowed_handicap, unrounded)
    assert result.playing_handicap == 10
  end

  test "plus allowance toward zero: CH -5 at 80%" do
    assert {:ok, result} = PlayingHandicap.calculate(D.new("-5"), 80)

    assert D.equal?(result.unrounded_allowed_handicap, D.new("-4"))
    assert result.playing_handicap == -4
  end

  test "negative half tie at 100% allowance rounds toward zero" do
    assert {:ok, result} = PlayingHandicap.calculate(D.new("-1.5"), 100)
    assert result.playing_handicap == -1
  end

  test "mixed tee stableford uses tee-specific course handicap without cross-tee adjustment" do
    {:ok, tee_a} = CourseHandicap.calculate(D.new("8.6"), 125, D.new("71.0"), 71)
    {:ok, tee_b} = CourseHandicap.calculate(D.new("15.0"), 140, D.new("74.0"), 72)

    refute D.equal?(tee_a.course_handicap_unrounded, tee_b.course_handicap_unrounded)

    assert {:ok, playing_a} = PlayingHandicap.calculate(tee_a.course_handicap_unrounded, 95)
    assert {:ok, playing_b} = PlayingHandicap.calculate(tee_b.course_handicap_unrounded, 95)

    refute playing_a.playing_handicap == playing_b.playing_handicap

    assert playing_a.playing_handicap ==
             CourseHandicap.whs_whole_number_round(
               D.mult(tee_a.course_handicap_unrounded, D.new("0.95"))
             )
  end
end
