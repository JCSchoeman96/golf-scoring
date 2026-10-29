defmodule GolfScoringWeb.CSPPolicyTest do
  use GolfScoringWeb.ConnCase, async: true

  test "browser responses use the production and test policy without broad WebSocket sources", %{
    conn: conn
  } do
    conn = get(conn, "/")
    assert [csp] = get_resp_header(conn, "content-security-policy")

    assert csp =~ "default-src 'self'"
    assert csp =~ "script-src 'self'"
    assert csp =~ "style-src 'self' 'unsafe-inline'"
    assert csp =~ "img-src 'self' data:"
    assert csp =~ "font-src 'self' data:"
    assert csp =~ "connect-src 'self'"
    refute csp =~ "ws:"
    refute csp =~ "wss:"
    assert csp =~ "object-src 'none'"
    assert csp =~ "base-uri 'self'"
    assert csp =~ "frame-ancestors 'none'"
    assert csp =~ "form-action 'self'"
    refute csp =~ "script-src 'self' 'unsafe-inline'"
  end

  test "the theme initializes from a synchronous same-origin asset before app.js", %{conn: conn} do
    conn = get(conn, "/")
    html = html_response(conn, 200)

    assert [theme_script] =
             Regex.run(~r/<script\b[^>]*src="\/assets\/js\/theme\.js"[^>]*>\s*<\/script>/, html)

    refute theme_script =~ "defer"

    assert {theme_position, _} = :binary.match(html, "/assets/js/theme.js")
    assert {app_position, _} = :binary.match(html, "/assets/js/app.js")
    assert theme_position < app_position

    refute html =~ "localStorage"
    refute html =~ "matchMedia"

    theme_asset = Path.expand("../../assets/js/theme.js", __DIR__)
    assert File.regular?(theme_asset)
    assert File.read!(theme_asset) =~ "localStorage"
    assert File.read!(theme_asset) =~ "matchMedia"
  end
end
