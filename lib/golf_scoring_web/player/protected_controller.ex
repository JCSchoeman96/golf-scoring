defmodule GolfScoringWeb.Player.ProtectedController do
  @moduledoc false

  use GolfScoringWeb, :controller

  def show(conn, _params) do
    text(conn, "player session active")
  end
end
