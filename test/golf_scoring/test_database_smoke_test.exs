defmodule GolfScoring.TestDatabaseSmokeTest do
  use GolfScoring.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias GolfScoring.Repo

  setup_all do
    probe_id = Ecto.UUID.generate() |> String.replace("-", "")
    probe_table = "gls_2_smoke_probe_#{probe_id}"

    Sandbox.unboxed_run(Repo, fn ->
      Repo.query!("CREATE TABLE #{probe_table} (id integer PRIMARY KEY)")
    end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Repo.query!("DROP TABLE IF EXISTS #{probe_table}")
      end)
    end)

    {:ok, probe_table: probe_table}
  end

  test "connects to the allocated PostgreSQL test database", %{probe_table: probe_table} do
    expected_database =
      Path.expand("../../.devcore/project.conf", __DIR__)
      |> File.read!()
      |> String.split("\n")
      |> Enum.find_value(fn
        "TEST_DB_NAME=" <> name -> String.trim(name)
        _ -> nil
      end)

    assert is_binary(expected_database)

    expected_database = expected_database <> System.get_env("MIX_TEST_PARTITION", "")

    assert %Postgrex.Result{rows: [[^expected_database]]} =
             Repo.query!("SELECT current_database()")

    assert_probe_is_empty(probe_table)
    write_probe_row(probe_table)
  end

  test "rolls back writes before the next test", %{probe_table: probe_table} do
    assert_probe_is_empty(probe_table)
    write_probe_row(probe_table)
  end

  defp assert_probe_is_empty(probe_table) do
    assert %Postgrex.Result{rows: [[0]]} =
             Repo.query!("SELECT count(*) FROM #{probe_table}")
  end

  defp write_probe_row(probe_table) do
    Repo.query!("INSERT INTO #{probe_table} (id) VALUES (1)")

    assert %Postgrex.Result{rows: [[1]]} =
             Repo.query!("SELECT count(*) FROM #{probe_table}")
  end
end
