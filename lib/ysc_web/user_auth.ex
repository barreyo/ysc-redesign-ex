defmodule YscWeb.UserAuth do
  use YscWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Ysc.Accounts
  alias Ysc.Customers
  alias Ysc.Subscriptions

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_ysc_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      YscWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    conn = assign(conn, :current_user, user)

    if user do
      active_membership = get_active_membership(user)
      conn = assign(conn, :current_membership, active_membership)
      assign(conn, :active_membership?, active_membership != nil)
    else
      conn = assign(conn, :current_membership, nil)
      assign(conn, :active_membership?, false)
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Handles mounting and authenticating the current_user in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_user` - Assigns current_user
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:ensure_authenticated` - Authenticates the user from the session,
      and assigns the current_user to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

    * `:redirect_if_user_is_authenticated` - Authenticates the user from the session.
      Redirects to signed_in_path if there's a logged user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the current_user:

      defmodule YscWeb.PageLive do
        use YscWeb, :live_view

        on_mount {YscWeb.UserAuth, :mount_current_user}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{YscWeb.UserAuth, :ensure_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    socket = mount_current_user(socket, session)
    {:cont, mount_current_membership(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)
    socket = mount_current_membership(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")

      {:halt, socket}
    end
  end

  def on_mount(:ensure_admin, _params, session, socket) do
    socket = mount_current_user(socket, session)
    socket = mount_current_membership(socket, session)

    if socket.assigns.current_user && socket.assigns.current_user.role == :admin do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You do not have permission to access this page")
        |> Phoenix.LiveView.redirect(to: ~p"/")

      {:halt, socket}
    end
  end

  def on_mount(:ensure_active, _params, session, socket) do
    socket = mount_current_user(socket, session)
    socket = mount_current_membership(socket, session)

    user = socket.assigns.current_user

    if user && user.state == :active do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "Your account is not active")
        |> Phoenix.LiveView.redirect(to: ~p"/pending-review")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)
    socket = mount_current_membership(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket))}
    else
      {:cont, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated_and_pending_approval, _params, session, socket) do
    socket = mount_current_user(socket, session)
    socket = mount_current_membership(socket, session)

    if socket.assigns.current_user do
      if socket.assigns.current_user.state == "pending_approval" do
        {:halt, Phoenix.LiveView.redirect(socket, to: not_approved_path(socket))}
      else
        {:cont, socket}
      end
    else
      {:cont, socket}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token)
      end
    end)
  end

  defp mount_current_membership(socket, _session) do
    socket =
      Phoenix.Component.assign_new(socket, :current_membership, fn ->
        if socket.assigns.current_user != nil do
          get_active_membership(socket.assigns.current_user)
        end
      end)

    Phoenix.Component.assign_new(socket, :active_membership?, fn ->
      socket.assigns.current_membership != nil
    end)
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  def require_admin(conn, _opts) do
    user = conn.assigns[:current_user]

    if user.role == :admin do
      conn
    else
      conn
      |> put_flash(:error, "You do not have permission to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  def require_approved(conn, _opts) do
    user = conn.assigns[:current_user]

    if user.state == :active do
      conn
    else
      conn
      |> put_flash(:error, "Your account has not been approved yet")
      |> redirect(to: ~p"/pending-review")
      |> halt()
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(%Plug.Conn{} = conn) do
    if user = conn.assigns[:current_user] do
      case user.state do
        :pending_approval -> ~p"/pending-review"
        _ -> ~p"/"
      end
    else
      ~p"/"
    end
  end

  defp signed_in_path(socket) do
    if user = socket.assigns[:current_user] do
      case user.state do
        :pending_approval -> ~p"/pending-review"
        _ -> ~p"/"
      end
    else
      ~p"/"
    end
  end

  defp not_approved_path(_conn), do: ~p"/pending-review"

  # Helper function to get the most expensive active membership
  defp get_active_membership(user) do
    # Check for lifetime membership first (highest priority)
    if Accounts.has_lifetime_membership?(user) do
      # Return a special struct representing lifetime membership
      %{
        type: :lifetime,
        awarded_at: user.lifetime_membership_awarded_at,
        user_id: user.id
      }
    else
      # Get all subscriptions for the user
      subscriptions = Customers.subscriptions(user)

      # Filter for active subscriptions only
      active_subscriptions =
        Enum.filter(subscriptions, fn subscription ->
          Subscriptions.valid?(subscription)
        end)

      case active_subscriptions do
        [] ->
          nil

        [single_subscription] ->
          single_subscription

        multiple_subscriptions ->
          # If multiple active subscriptions, pick the most expensive one
          get_most_expensive_subscription(multiple_subscriptions)
      end
    end
  end

  # Helper function to determine the most expensive subscription
  defp get_most_expensive_subscription(subscriptions) do
    membership_plans = Application.get_env(:ysc, :membership_plans)

    # Create a map of price_id to amount for quick lookup
    price_to_amount =
      Map.new(membership_plans, fn plan ->
        {plan.stripe_price_id, plan.amount}
      end)

    # Find the subscription with the highest amount
    Enum.max_by(subscriptions, fn subscription ->
      # Get the first subscription item (assuming one item per subscription)
      case subscription.subscription_items do
        [item | _] ->
          Map.get(price_to_amount, item.stripe_price_id, 0)

        _ ->
          0
      end
    end)
  end
end
