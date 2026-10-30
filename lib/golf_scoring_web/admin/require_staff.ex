defmodule GolfScoringWeb.Admin.RequireStaff do
  @moduledoc false

  import Phoenix.Controller, only: [redirect: 2]
  import Plug.Conn

  alias GolfScoring.Accounts.StaffUser

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{assigns: %{current_staff_user: %StaffUser{status: :active}}} = conn, _opts) do
    conn
  end

  def call(conn, _opts) do
    conn
    |> redirect(to: "/admin/sign-in")
    |> halt()
  end
end
