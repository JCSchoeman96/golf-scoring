defmodule GolfScoringWeb.PageController do
  use GolfScoringWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
