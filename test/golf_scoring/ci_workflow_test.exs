defmodule GolfScoring.CIWorkflowTest do
  use ExUnit.Case, async: true

  @workflow_path Path.expand("../../.github/workflows/ci.yml", __DIR__)
  @required_environment [
    "TEST_DATABASE_USERNAME",
    "TEST_DATABASE_PASSWORD",
    "TEST_DATABASE_HOST",
    "TEST_DATABASE_PORT",
    "TEST_DATABASE_NAME"
  ]
  @required_commands [
    "mix deps.get --check-locked",
    "mix format --check-formatted",
    "mix compile --warnings-as-errors",
    "mix credo --strict",
    "mix ash.codegen --check",
    "mix deps.unlock --check-unused",
    "mix hex.audit",
    "mix sobelow --exit --strict --format github --private",
    "mix test --cover",
    "mix dialyzer --plt",
    "mix dialyzer --format github --format dialyxir"
  ]

  test "Dialyzer includes ExUnit in the test PLT for support modules" do
    assert :ex_unit in Keyword.get(Mix.Project.config()[:dialyzer], :plt_add_apps, [])
  end

  test "GitHub Actions runs the Phase 0 quality gate on pull requests and main pushes" do
    assert File.regular?(@workflow_path),
           "expected .github/workflows/ci.yml to define the repository CI workflow"

    workflow = File.read!(@workflow_path)

    assert workflow =~ ~r/^on:\s*$/m
    assert workflow =~ ~r/^  pull_request:\s*$/m
    assert workflow =~ ~r/^  push:\s*$/m
    assert workflow =~ ~r/^    branches:\s*$/m
    assert workflow =~ ~r/^      - main\s*$/m

    assert workflow =~ ~r/^permissions:\s*\n  contents:\s*read\s*$/m
    refute workflow =~ ~r/\b(write|id-token)\b/

    assert workflow =~ ~r/^jobs:\s*$/m

    job_names =
      workflow
      |> String.split(~r/^jobs:\s*$/m, parts: 2)
      |> List.last()
      |> then(&Regex.scan(~r/^  ([A-Za-z0-9_-]+):\s*$/m, &1, capture: :all_but_first))
      |> List.flatten()

    assert job_names == ["quality", "security", "test", "dialyzer"]

    assert workflow =~ "actions/checkout v7.0.1"
    assert workflow =~ "uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
    assert workflow =~ "erlef/setup-beam v1.24.1"
    assert workflow =~ "uses: erlef/setup-beam@54075bcc5e249e4758d363f27d099f55d843f124"
    assert workflow =~ "ELIXIR_VERSION: \"1.19.3\""
    assert workflow =~ "OTP_VERSION: \"28.1.1\""

    assert workflow =~ ~r/^      postgres:\s*$/m
    assert workflow =~ "image: postgres:18"
    assert workflow =~ "pg_isready"

    for variable <- @required_environment do
      assert Regex.match?(Regex.compile!("^ {6}#{variable}: .+$", "m"), workflow),
             "expected CI to set #{variable} explicitly"
    end

    assert workflow =~ "TEST_DATABASE_NAME: golf_scoring_test"
    refute workflow =~ "MIX_TEST_PARTITION"

    command_positions =
      Enum.map(@required_commands, fn command ->
        assert {position, _length} = :binary.match(workflow, command),
               "expected CI to run #{command} explicitly"

        position
      end)

    assert command_positions == Enum.sort(command_positions)
    refute workflow =~ ~r/^\s*matrix:\s*$/m
    refute workflow =~ ~r/^\s*redis:\s*$/mi
  end
end
