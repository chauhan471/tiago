defmodule TiagoWeb.Router do
  use TiagoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TiagoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :guardian do
    plug Guardian.Plug.Pipeline,
      module: Tiago.Auth.Guardian,
      error_handler: TiagoWeb.AuthErrorHandler
    plug Guardian.Plug.VerifySession
    plug Guardian.Plug.LoadResource, allow_blank: true
  end

  pipeline :require_auth do
    plug TiagoWeb.Plugs.RequireAuth
  end

  pipeline :require_org do
    plug TiagoWeb.Plugs.RequireOrg
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Public routes (shared ledger links)
  scope "/", TiagoWeb do
    pipe_through [:browser, :guardian]

    get "/", PageController, :home
    live "/shared/:token", SharedLedgerLive
  end

  # Auth routes (login/register — unauthenticated)
  scope "/", TiagoWeb do
    pipe_through [:browser, :guardian]

    live "/register", AuthLive.Register
    live "/login", AuthLive.Login
    post "/session", SessionController, :create
    delete "/session", SessionController, :delete
  end

  # Authenticated routes (no org required — org selection)
  scope "/", TiagoWeb do
    pipe_through [:browser, :guardian, :require_auth]

    live "/organizations", OrgLive.Index
    live "/organizations/new", OrgLive.New
    post "/organizations/select", OrgController, :select
  end

  # Org-scoped routes (auth + org required)
  scope "/", TiagoWeb do
    pipe_through [:browser, :guardian, :require_auth, :require_org]

    live "/dashboard", DashboardLive, :index
    live "/parties", PartyLive.Index, :index
    live "/parties/new", PartyLive.Index, :new
    live "/parties/:id/edit", PartyLive.Index, :edit
    live "/parties/:id", PartyLive.Show, :show
    live "/parties/:id/ledger", LedgerLive.Show, :show
    live "/uploads", UploadLive.Index, :index
    live "/settings", OrgLive.Settings, :index
    live "/settings/shared-links", OrgLive.SharedLinks, :index

    get "/parties/:id/ledger/pdf", ExportController, :party_ledger_pdf
    get "/parties/:id/ledger/csv", ExportController, :party_ledger_csv
  end

  # Dev routes
  if Application.compile_env(:tiago, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: TiagoWeb.Telemetry
    end
  end
end
