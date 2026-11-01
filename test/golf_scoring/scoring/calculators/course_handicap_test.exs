defmodule GolfScoring.Scoring.Calculators.CourseHandicapTest do
  use ExUnit.Case, async: true

  alias Decimal, as: D
  alias GolfScoring.Scoring.Calculators.CourseHandicap

  test "slope 113 baseline: HI 8.0 CR 72 par 72" do
    assert {:ok, result} =
             CourseHandicap.calculate(D.new("8.0"), 113, D.new("72.0"), 72)

    assert D.equal?(result.course_handicap_unrounded, D.new("8.0"))
    assert result.course_handicap_rounded == 8
  end

  test "rating minus par adds one stroke to course handicap" do
    assert {:ok, result} =
             CourseHandicap.calculate(D.new("8.0"), 113, D.new("73.0"), 72)

    assert D.equal?(result.course_handicap_unrounded, D.new("9.0"))
    assert result.course_handicap_rounded == 9
  end

  test "current WHS example HI 8.6 slope 125 CR 71 par 71" do
    assert {:ok, result} =
             CourseHandicap.calculate(D.new("8.6"), 125, D.new("71.0"), 71)

    assert D.equal?(
             D.round(result.course_handicap_unrounded, 4),
             D.new("9.5133")
           )

    assert result.course_handicap_rounded == 10
  end

  test "WHS whole-number rounding positive half tie rounds toward larger integer" do
    assert CourseHandicap.whs_whole_number_round(D.new("1.4")) == 1
    assert CourseHandicap.whs_whole_number_round(D.new("1.5")) == 2
    assert CourseHandicap.whs_whole_number_round(D.new("1.6")) == 2
  end

  test "WHS whole-number rounding negative half tie rounds toward larger integer (toward zero for plus)" do
    assert CourseHandicap.whs_whole_number_round(D.new("-1.4")) == -1
    assert CourseHandicap.whs_whole_number_round(D.new("-1.5")) == -1
    assert CourseHandicap.whs_whole_number_round(D.new("-1.6")) == -2
  end

  test "unrounded course handicap is not pre-rounded before storage field" do
    assert {:ok, result} =
             CourseHandicap.calculate(D.new("8.6"), 125, D.new("71.0"), 71)

    refute D.equal?(result.course_handicap_unrounded, D.new("10"))
    assert D.compare(result.course_handicap_unrounded, D.new("9.5")) == :gt
    assert D.compare(result.course_handicap_unrounded, D.new("9.6")) == :lt
  end

  test "multiply-before-divide preserves exact positive 0.5 course handicap tie" do
    assert {:ok, result} =
             CourseHandicap.calculate(D.new("11.3"), 62, D.new("66.3"), 72)

    assert D.equal?(result.course_handicap_unrounded, D.new("0.5"))
    assert result.course_handicap_rounded == 1
  end

  test "multiply-before-divide preserves exact negative 0.5 course handicap tie" do
    assert {:ok, result} =
             CourseHandicap.calculate(D.new("11.3"), 62, D.new("65.3"), 72)

    assert D.equal?(result.course_handicap_unrounded, D.new("-0.5"))
    assert result.course_handicap_rounded == 0
  end
end
