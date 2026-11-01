defmodule GolfScoring.Scoring.Calculators.CountbackTest do
  use ExUnit.Case, async: true

  alias GolfScoring.Scoring.Calculators.Countback

  defp contribution(physical_hole_number, opts \\ []) do
    points = Keyword.get(opts, :points, physical_hole_number)
    mystery_hole? = Keyword.get(opts, :mystery_hole?, false)

    %{
      physical_hole_number: physical_hole_number,
      points: points,
      mystery_hole?: mystery_hole?
    }
  end

  defp identity_fixture_contributions(mystery_holes \\ MapSet.new()) do
    for hole <- 1..18 do
      contribution(hole, mystery_hole?: MapSet.member?(mystery_holes, hole))
    end
  end

  defp shotgun_order(contributions) do
    order = [14, 15, 16, 17, 18, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]

    by_hole = Map.new(contributions, &{&1.physical_hole_number, &1})
    Enum.map(order, &Map.fetch!(by_hole, &1))
  end

  describe "standard_countback" do
    test "produces exact seven-component tie-break key in physical-hole order" do
      contributions = identity_fixture_contributions()

      assert {:ok, %{tie_break_key: key}} =
               Countback.calculate(contributions, :standard_countback)

      assert key == [126, 93, 51, 18, 39, 24, 9]
    end

    test "list input order does not affect key (shotgun-style order)" do
      contributions = identity_fixture_contributions()
      shotgun = shotgun_order(contributions)

      assert {:ok, %{tie_break_key: canonical}} =
               Countback.calculate(contributions, :standard_countback)

      assert {:ok, %{tie_break_key: shotgun_key}} =
               Countback.calculate(shotgun, :standard_countback)

      assert shotgun_key == canonical
    end

    test "identical inputs are deterministic" do
      contributions = identity_fixture_contributions()

      assert Countback.calculate(contributions, :standard_countback) ==
               Countback.calculate(contributions, :standard_countback)
    end

    test "fully tied inputs return identical keys" do
      contributions = identity_fixture_contributions()

      assert {:ok, a} = Countback.calculate(contributions, :standard_countback)
      assert {:ok, b} = Countback.calculate(contributions, :standard_countback)
      assert a.tie_break_key == b.tie_break_key
    end

    test "zero-point contributions work" do
      contributions =
        for hole <- 1..18 do
          contribution(hole, points: 0)
        end

      assert {:ok, %{tie_break_key: key}} =
               Countback.calculate(contributions, :standard_countback)

      assert key == [0, 0, 0, 0, 0, 0, 0]
    end

    test "points above four are not capped" do
      contributions =
        for hole <- 1..18 do
          contribution(hole, points: hole + 10)
        end

      assert {:ok, %{tie_break_key: key}} =
               Countback.calculate(contributions, :standard_countback)

      # sums use uncapped per-hole points (hole n has points n + 10)
      assert key == [126 + 9 * 10, 93 + 6 * 10, 51 + 3 * 10, 28, 39 + 6 * 10, 24 + 3 * 10, 19]
    end
  end

  describe "mystery_holes_then_countback" do
    test "mystery subtotal precedes standard countback components" do
      mystery_holes = MapSet.new([2, 7, 15])
      contributions = identity_fixture_contributions(mystery_holes)

      assert {:ok, %{tie_break_key: key}} =
               Countback.calculate(contributions, :mystery_holes_then_countback)

      assert key == [24, 126, 93, 51, 18, 39, 24, 9]
    end

    test "mystery subtotal uses supplied points not hole numbers when overridden" do
      contributions =
        for hole <- 1..18 do
          points =
            cond do
              hole == 2 -> 100
              hole == 7 -> 5
              hole == 15 -> 1
              true -> hole
            end

          contribution(hole,
            points: points,
            mystery_hole?: hole in [2, 7, 15]
          )
        end

      assert {:ok, %{tie_break_key: key}} =
               Countback.calculate(contributions, :mystery_holes_then_countback)

      assert hd(key) == 106
      assert tl(key) == [112, 79, 51, 18, 37, 22, 9]
    end
  end

  describe "input validation" do
    test "rejects non-list contributions" do
      assert {:error, :invalid_input} = Countback.calculate(%{}, :standard_countback)
      assert {:error, :invalid_input} = Countback.calculate(nil, :standard_countback)
    end

    test "requires exactly 18 contributions" do
      short = for hole <- 1..17, do: contribution(hole)
      long = for hole <- 1..19, do: contribution(hole)

      assert {:error, :invalid_input} = Countback.calculate(short, :standard_countback)
      assert {:error, :invalid_input} = Countback.calculate(long, :standard_countback)
    end

    test "rejects duplicate physical hole" do
      contributions =
        for hole <- 1..17, do: contribution(hole)

      contributions = [contribution(1) | contributions]

      assert {:error, :invalid_input} =
               Countback.calculate(contributions, :standard_countback)
    end

    test "rejects missing physical hole" do
      contributions = for hole <- 2..18, do: contribution(hole)

      assert {:error, :invalid_input} =
               Countback.calculate(contributions, :standard_countback)
    end

    test "rejects out-of-range physical hole" do
      contributions =
        for hole <- 1..17, do: contribution(hole)

      contributions = contributions ++ [contribution(19)]

      assert {:error, :invalid_input} =
               Countback.calculate(contributions, :standard_countback)

      contributions_low = for hole <- 0..16, do: contribution(hole)

      assert {:error, :invalid_input} =
               Countback.calculate(contributions_low, :standard_countback)
    end

    test "rejects negative points" do
      contributions =
        for hole <- 1..18 do
          points = if hole == 5, do: -1, else: hole
          contribution(hole, points: points)
        end

      assert {:error, :invalid_input} =
               Countback.calculate(contributions, :standard_countback)
    end

    test "rejects float points" do
      contributions =
        for hole <- 1..18 do
          points = if hole == 5, do: 1.0, else: hole
          contribution(hole, points: points)
        end

      assert {:error, :invalid_input} =
               Countback.calculate(contributions, :standard_countback)
    end

    test "rejects nil points" do
      contributions =
        for hole <- 1..18 do
          points = if hole == 5, do: nil, else: hole
          contribution(hole, points: points)
        end

      assert {:error, :invalid_input} =
               Countback.calculate(contributions, :standard_countback)
    end

    test "rejects string points" do
      contributions =
        for hole <- 1..18 do
          points = if hole == 5, do: "3", else: hole
          contribution(hole, points: points)
        end

      assert {:error, :invalid_input} =
               Countback.calculate(contributions, :standard_countback)
    end

    test "rejects non-boolean mystery_hole?" do
      contributions =
        for hole <- 1..18 do
          base = contribution(hole)
          if hole == 3, do: Map.put(base, :mystery_hole?, "yes"), else: base
        end

      assert {:error, :invalid_input} =
               Countback.calculate(contributions, :mystery_holes_then_countback)
    end

    test "rejects malformed map missing required keys" do
      contributions =
        for hole <- 1..18 do
          if hole == 10,
            do: %{physical_hole_number: 10, points: 10},
            else: contribution(hole)
        end

      assert {:error, :invalid_input} =
               Countback.calculate(contributions, :mystery_holes_then_countback)
    end
  end

  describe "policy" do
    test "rejects unsupported policy" do
      contributions = identity_fixture_contributions()

      assert {:error, :unsupported_policy} =
               Countback.calculate(contributions, :last_nine)
    end
  end
end
