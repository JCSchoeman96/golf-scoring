defmodule GolfScoringWeb.Router do
  use GolfScoringWeb, :router

  @browser_headers %{
    "content-security-policy" =>
      "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self' ws: wss:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'"
  }

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GolfScoringWeb.Layouts, :root}
    plug :protect_from_forgery

    plug :put_secure_browser_headers, @browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GolfScoringWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", GolfScoringWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:golf_scoring, :dev_routes) do
    @dev_dashboard_headers %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self' ws: wss:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'"
    }

    pipeline :dev_dashboard do
      plug :put_secure_browser_headers, @dev_dashboard_headers
    end

    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:browser, :dev_dashboard]

      live_dashboard "/dashboard", metrics: GolfScoringWeb.Telemetry
    end
  end
end
