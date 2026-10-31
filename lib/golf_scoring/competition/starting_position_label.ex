defmodule GolfScoring.Competition.StartingPositionLabel do
  @moduledoc false

  @spec format(pos_integer(), pos_integer()) :: String.t()
  def format(display_hole_number, starting_position)
      when is_integer(display_hole_number) and display_hole_number > 0 and
             is_integer(starting_position) and starting_position > 0 do
    "#{display_hole_number}#{position_letter(starting_position)}"
  end

  @spec position_letter(non_neg_integer()) :: String.t()
  def position_letter(0), do: ""

  def position_letter(n) when n > 0 do
    position_letter(div(n - 1, 26)) <> <<rem(n - 1, 26) + ?A>>
  end
end
