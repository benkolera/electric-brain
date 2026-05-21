defmodule ElectricbrainWeb.Router do
  use ElectricbrainWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ElectricbrainWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  # ALB target group health check — outside :browser, no auth, no session.
  # Must remain excluded from force_ssl (config/prod.exs) so the ALB's
  # HTTP probe doesn't get a 301.
  scope "/", ElectricbrainWeb do
    get "/health", HealthController, :index
  end

  scope "/", ElectricbrainWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes,
      on_mount: {ElectricbrainWeb.LiveUserAuth, :live_user_required} do
      live "/", HomeLive, :index

      live "/notes", NoteLive.Index, :index
      live "/notes/new", NoteLive.Form, :new
      live "/notes/:id", NoteLive.Show, :show
      live "/notes/:id/edit", NoteLive.Form, :edit

      live "/todos", TodoLive.Index, :index
      live "/todos/:id/schedule", TodoLive.Schedule, :show

      live "/habits", HabitLive.Index, :index
      live "/habits/:id/edit", HabitLive.Edit, :show

      live "/time-blocks", TimeBlockLive.Index, :index
      live "/time-blocks/:id/edit", TimeBlockLive.Edit, :show

      live "/categories", CategoryLive.Index, :index

      live "/metrics", MetricLive.Index, :index
      live "/metrics/:id", MetricLive.Show, :show

      live "/moments", MomentLive.Index, :index
      live "/moments/new", MomentLive.New, :new
      live "/moments/:id", MomentLive.Show, :show

      live "/plan", PlannerLive.Index, :index
      live "/plan/review", PlannerLive.Review, :index

      live "/settings", SettingsLive, :index

      live "/help", HelpLive, :index
    end

    scope "/oauth/google", as: :google_oauth do
      get "/start", GoogleOAuthController, :start
      get "/callback", GoogleOAuthController, :callback
    end
  end

  scope "/", ElectricbrainWeb do
    pipe_through :browser

    auth_routes AuthController, Electricbrain.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Dev/test exposes /register so a local user can be created via the
    # password form. Prod is Auth0-only — no register_path means /register
    # 404s and the sign-in page only shows the Auth0 button.
    if Mix.env() in [:dev, :test] do
      sign_in_route register_path: "/register",
                    auth_routes_prefix: "/auth",
                    on_mount: [{ElectricbrainWeb.LiveUserAuth, :live_no_user}],
                    overrides: [
                      ElectricbrainWeb.AuthOverrides,
                      Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                    ]
    else
      sign_in_route auth_routes_prefix: "/auth",
                    on_mount: [{ElectricbrainWeb.LiveUserAuth, :live_no_user}],
                    overrides: [
                      ElectricbrainWeb.AuthOverrides,
                      Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                    ]
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", ElectricbrainWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:electricbrain, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ElectricbrainWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
