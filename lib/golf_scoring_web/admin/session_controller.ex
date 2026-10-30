defmodule GolfScoringWeb.Admin.SessionController do
  use GolfScoringWeb, :controller
  use AshAuthentication.Phoenix.Controller

  @impl AshAuthentication.Phoenix.Controller
  def success(conn, _activity, staff_user, _token) do
    conn
    |> store_in_session(staff_user)
    |> assign(:current_staff_user, staff_user)
    |> redirect(to: "/admin")
  end

  @impl AshAuthentication.Phoenix.Controller
  def failure(conn, _activity, _reason) do
    send_resp(conn, :unauthorized, "Authentication failed")
  end

  @impl AshAuthentication.Phoenix.Controller
  def sign_out(conn, _params) do
    conn
    |> clear_session(:golf_scoring)
    |> redirect(to: "/admin/sign-in")
  end

  def foundation(conn, _params) do
    send_resp(conn, :no_content, "")
  end
end
