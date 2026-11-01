defmodule GolfScoring.Scoring.Policies.PickupEligibilityTest do
  use ExUnit.Case, async: true

  alias GolfScoring.Scoring.Policies.PickupEligibility

  defp decide(strokes_taken, opts \\ []) do
    PickupEligibility.decide(%{
      pickup_policy_identifier: Keyword.get(opts, :policy, "standard_pickup_v1"),
      par: Keyword.get(opts, :par, 4),
      allocated_strokes: Keyword.get(opts, :allocated_strokes, 0),
      strokes_taken: strokes_taken
    })
  end

  test "scratch player one stroke before zero-point inevitability is ineligible" do
    assert {:ok, %{eligible?: false, reason: :point_still_possible}} = decide(4)
  end

  test "scratch player at first zero-point state is eligible" do
    assert {:ok, %{eligible?: true, reason: :no_point_possible}} = decide(5)
  end

  test "player receiving a stroke has shifted pickup threshold" do
    assert {:ok, %{eligible?: false, reason: :point_still_possible}} =
             decide(5, allocated_strokes: 1)

    assert {:ok, %{eligible?: true, reason: :no_point_possible}} =
             decide(6, allocated_strokes: 1)
  end

  test "plus player giving back a stroke has shifted pickup threshold" do
    assert {:ok, %{eligible?: false, reason: :point_still_possible}} =
             decide(3, allocated_strokes: -1)

    assert {:ok, %{eligible?: true, reason: :no_point_possible}} =
             decide(4, allocated_strokes: -1)
  end

  test "unknown pickup policy returns explicit error" do
    assert {:error, :unsupported_pickup_policy} =
             decide(5, policy: "mystery_pickup_v99")
  end

  test "decision API is player-local and accepts only hole context fields" do
    assert {:ok, _result} = decide(4)

    assert {:error, :invalid_context} =
             PickupEligibility.decide(%{
               pickup_policy_identifier: "standard_pickup_v1",
               par: 4,
               allocated_strokes: 0,
               strokes_taken: 4,
               partner_points: 4,
               side_best_ball_points: 3
             })
  end
end
