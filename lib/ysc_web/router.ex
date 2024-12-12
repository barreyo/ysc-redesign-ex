defmodule YscWeb.Router do
  use YscWeb, :router

  import Phoenix.LiveDashboard.Router
  import YscWeb.UserAuth
  import YscWeb.Plugs.SiteSettingsPlugs

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {YscWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug :mount_site_settings
  end

  pipeline :admin_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {YscWeb.Layouts, :admin_root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug :mount_site_settings
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", YscWeb do
    pipe_through [:browser, :mount_site_settings]

    get "/", PageController, :home

    live_session :mount_site_settings,
      on_mount: [
        {YscWeb.UserAuth, :mount_current_user},
        {YscWeb.Plugs.SiteSettingsPlugs, :mount_site_settings}
      ] do
      live "/posts/:id", PostLive, :index

      live "/events", EventsLive, :index

      live "/news", NewsLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", YscWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ysc, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", YscWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [
        {YscWeb.UserAuth, :redirect_if_user_is_authenticated},
        {YscWeb.Plugs.SiteSettingsPlugs, :mount_site_settings}
      ] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", YscWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [
        {YscWeb.UserAuth, :ensure_authenticated},
        {YscWeb.Plugs.SiteSettingsPlugs, :mount_site_settings}
      ] do
      get "/pending_review", PageController, :pending_review

      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", YscWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [
        {YscWeb.UserAuth, :mount_current_user},
        {YscWeb.Plugs.SiteSettingsPlugs, :mount_site_settings}
      ] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end

  scope "/admin", YscWeb do
    pipe_through [:admin_browser, :require_authenticated_user, :require_admin]

    live_dashboard "/dashboard", metrics: YscWeb.Telemetry

    # Handle uploads from editors
    post "/trix-uploads", TrixUploadsController, :create

    live_session :require_admin,
      on_mount: [
        {YscWeb.UserAuth, :ensure_authenticated},
        {YscWeb.UserAuth, :ensure_admin},
        {YscWeb.Plugs.SiteSettingsPlugs, :mount_site_settings}
      ] do
      live "/", AdminDashboardLive, :index

      # Handling media gallery
      live "/media", AdminMediaLive, :index
      live "/media/upload", AdminMediaLive, :upload
      live "/media/upload/:id", AdminMediaLive, :edit

      # User management
      live "/users", AdminUsersLive, :index
      live "/users/:id", AdminUsersLive, :edit
      live "/users/:id/review", AdminUsersLive, :review
      live "/users/:id/details", AdminUserDetailsLive, :profile
      live "/users/:id/details/orders", AdminUserDetailsLive, :orders
      live "/users/:id/details/bookings", AdminUserDetailsLive, :bookings
      live "/users/:id/details/application", AdminUserDetailsLive, :application

      # Money
      live "/money", AdminMoneyLive, :index

      # Events
      live "/events", AdminEventsLive, :index
      live "/events/new", AdminEventsNewLive, :new
      live "/events/:id/edit", AdminEventsNewLive, :edit
      live "/events/:id/tickets", AdminEventsNewLive, :tickets

      # Tahoe and Clear Lake settings etc, see bookings
      live "/bookings", AdminBookingsLive, :index

      # News and notices
      live "/posts", AdminPostsLive, :index
      live "/posts/new", AdminPostsLive, :new
      live "/posts/:id", AdminPostEditorLive, :edit
      live "/posts/:id/preview", AdminPostEditorLive, :preview
      live "/posts/:id/settings", AdminPostEditorLive, :settings

      # Website specific settings (such as socials etc)
      live "/settings", AdminSettingsLive, :index
    end
  end
end
