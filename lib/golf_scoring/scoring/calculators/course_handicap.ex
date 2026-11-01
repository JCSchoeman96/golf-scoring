defmodule GolfScoring.Scoring.Calculators.CourseHandicap do
  @moduledoc """
  Pure WHS course handicap from handicap index and frozen tee rating facts.
  """

  alias Decimal, as: D

  @standard_slope 113

  @doc """
  Computes course handicap from handicap index, slope rating, course rating, and par.

  Returns `{:ok, %{course_handicap_unrounded: decimal, course_handicap_rounded: integer}}`.
  """
  @spec calculate(D.t(), pos_integer(), D.t(), integer()) ::
          {:ok,
           %{
             course_handicap_unrounded: D.t(),
             course_handicap_rounded: integer()
           }}
  def calculate(handicap_index, slope_rating, course_rating, par)
      when is_integer(slope_rating) and is_integer(par) do
    slope = D.new(slope_rating)
    standard = D.new(@standard_slope)
    par_decimal = D.new(par)

    index_component =
      handicap_index
      |> D.mult(slope)
      |> D.div(standard)
      |> D.add(D.sub(course_rating, par_decimal))

    {:ok,
     %{
       course_handicap_unrounded: index_component,
       course_handicap_rounded: whs_whole_number_round(index_component)
     }}
  end

  @doc false
  @spec whs_whole_number_round(D.t()) :: integer()
  def whs_whole_number_round(%D{} = value) do
    case D.compare(value, D.new("0")) do
      :eq ->
        0

      :gt ->
        value
        |> D.add(D.new("0.5"))
        |> D.round(0, :floor)
        |> D.to_integer()

      :lt ->
        abs_value = D.abs(value)
        truncated = D.round(abs_value, 0, :down)
        remainder = D.sub(abs_value, truncated)
        base = D.to_integer(truncated)

        case D.compare(remainder, D.new("0.5")) do
          :lt -> -base
          :gt -> -(base + 1)
          :eq -> -base
        end
    end
  end
end
