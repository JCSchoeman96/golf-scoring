defmodule GolfScoring.ProjectQualityGateTest do
  use ExUnit.Case, async: true

  @required_commands [
    "format --check-formatted",
    "compile --warnings-as-errors",
    "test"
  ]

  @mutating_commands ["deps.unlock --unused", "format"]

  test "precommit checks the project without repairing the repository" do
    precommit =
      Mix.Project.config()
      |> Keyword.fetch!(:aliases)
      |> Keyword.fetch!(:precommit)

    missing = Enum.reject(@required_commands, &(&1 in precommit))
    mutating = Enum.filter(precommit, &(&1 in @mutating_commands))
    required_in_order = Enum.filter(precommit, &(&1 in @required_commands))

    assert missing == [] and mutating == [] and required_in_order == @required_commands,
           "precommit alias contract failed; missing checks: #{inspect(missing)}; " <>
             "forbidden mutating commands: #{inspect(mutating)}; " <>
             "required checks in order: #{inspect(required_in_order)}"
  end
end
