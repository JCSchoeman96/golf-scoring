defmodule GolfScoring.Scoring.Calculators.PlayingHandicap do
  @moduledoc """
  Pure playing handicap from unrounded course handicap and explicit allowance.
  """

  alias Decimal, as: D
  alias GolfScoring.Scoring.Calculators.CourseHandicap

  @doc """
  Applies competition allowance to unrounded course handicap.

  Returns `{:ok, %{unrounded_allowed_handicap: decimal, playing_handicap: integer}}`.
  """
  @spec calculate(D.t(), non_neg_integer()) ::
          {:ok,
           %{
             unrounded_allowed_handicap: D.t(),
             playing_handicap: integer()
           }}
  def calculate(course_handicap_unrounded, handicap_allowance_percent)
      when is_integer(handicap_allowance_percent) and handicap_allowance_percent >= 0 and
             handicap_allowance_percent <= 100 do
    percent = D.new(handicap_allowance_percent)
    hundred = D.new("100")

    unrounded_allowed =
      course_handicap_unrounded
      |> D.mult(percent)
      |> D.div(hundred)

    {:ok,
     %{
       unrounded_allowed_handicap: unrounded_allowed,
       playing_handicap: CourseHandicap.whs_whole_number_round(unrounded_allowed)
     }}
  end
end
