defmodule HierbautberlinWeb.Router do
  use HierbautberlinWeb, :router

  import HierbautberlinWeb.UserAuth
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {HierbautberlinWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :backend do
    plug HierbautberlinWeb.Plugs.AllowedForBackend
  end

  scope "/" do
    pipe_through [:browser, :require_authenticated_user, :backend]

    live_dashboard "/dashboard",
      metrics: HierbautberlinWeb.Telemetry,
      ecto_repos: [Hierbautberlin.Repo]
  end

  scope "/", HierbautberlinWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
    get "/users/reset_password", UserResetPasswordController, :new
    post "/users/reset_password", UserResetPasswordController, :create
    get "/users/reset_password/:token", UserResetPasswordController, :edit
    put "/users/reset_password/:token", UserResetPasswordController, :update
  end

  scope "/", HierbautberlinWeb do
    pipe_through [:browser, :require_authenticated_user]

    delete "/users", UserSettingsController, :delete
    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm_email/:token", UserSettingsController, :confirm_email

    resources "/users/subscriptions", SubscriptionsController, only: [:index, :update, :delete]
  end

  scope "/", HierbautberlinWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete
    get "/users/confirm", UserConfirmationController, :new
    post "/users/confirm", UserConfirmationController, :create
    get "/users/confirm/:token", UserConfirmationController, :confirm

    get "/", WelcomeController, :index
    get "/impressum", ImpressumController, :index
    get "/datenschutz", PrivacyController, :index
    get "/ping", HealthcheckController, :index

    get "/view_pdf/*path", ViewPDFController, :show

    live "/map", MapLive, :index
  end

  if Application.get_env(:hierbautberlin, :environment) == :dev do
    forward "/sent_emails", Bamboo.SentEmailViewerPlug
  end
end
