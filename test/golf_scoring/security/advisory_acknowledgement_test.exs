defmodule GolfScoring.Security.AdvisoryAcknowledgementTest do
  use ExUnit.Case, async: true

  alias AshAuthentication.Info
  alias GolfScoring.Accounts.StaffUser

  @acknowledged_cve "CVE-2026-117656"
  @assent_patched_version "0.3.2"

  @assent_external_identity_strategy_modules [
    AshAuthentication.Strategy.OAuth2,
    AshAuthentication.Strategy.Oidc,
    AshAuthentication.Strategy.Apple
  ]

  @drift_message """
  CVE-2026-117656 is acknowledged only because this application does not use \
  Assent-backed external identity authentication. Remove the acknowledgement \
  and upgrade to patched Assent before enabling Apple/OAuth2/OIDC authentication.
  """

  test "acknowledges only CVE-2026-117656 for unreachable Assent Apple advisory" do
    ignored = Mix.Project.config()[:hex][:ignore_advisories] || []

    assert ignored == [@acknowledged_cve],
           "expected hex ignore_advisories to contain exactly #{@acknowledged_cve}"
  end

  test "StaffUser configures password authentication only" do
    strategies = Info.list_strategies(StaffUser)

    assert strategies != [],
           "expected StaffUser to declare at least one authentication strategy"

    external =
      Enum.filter(strategies, fn strategy ->
        strategy.__struct__ in @assent_external_identity_strategy_modules
      end)

    assert external == [], @drift_message

    password_only? =
      Enum.all?(strategies, fn strategy ->
        strategy.__struct__ == AshAuthentication.Strategy.Password
      end)

    assert password_only?,
           @drift_message <>
             " Found: #{inspect(Enum.map(strategies, fn strategy -> strategy.__struct__ end))}"
  end

  test "AshAuthentication 4.x still constrains Assent below 0.3.0" do
    ash_authentication_lock =
      "mix.lock"
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.find(&String.contains?(&1, "\"ash_authentication\""))

    assert ash_authentication_lock,
           "expected ash_authentication entry in mix.lock"

    assert ash_authentication_lock =~ ~S/assent, "> 0.2.0 and < 0.3.0"/,
           "expected stable AshAuthentication to constrain Assent below 0.3.0"
  end

  test "stale CVE-2026-117656 acknowledgement fails once Assent is patched" do
    ignored = Mix.Project.config()[:hex][:ignore_advisories] || []

    unless @acknowledged_cve in ignored do
      flunk("expected #{@acknowledged_cve} to remain in hex ignore_advisories for this contract")
    end

    case locked_assent_version() do
      nil ->
        flunk("expected :assent application to be loaded in the test environment")

      version ->
        if Version.compare(version, Version.parse!(@assent_patched_version)) != :lt do
          flunk(
            "Assent #{version} is patched; remove obsolete hex ignore_advisories entry for #{@acknowledged_cve}"
          )
        end
    end
  end

  defp locked_assent_version do
    case Application.spec(:assent, :vsn) do
      nil -> nil
      vsn -> vsn |> to_string() |> Version.parse!()
    end
  end
end
