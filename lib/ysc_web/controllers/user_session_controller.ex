defmodule YscWeb.UserSessionController do
  use YscWeb, :controller

  alias Ysc.Accounts
  alias Ysc.Accounts.AuthService
  alias YscWeb.UserAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  def auto_login(conn, %{"token" => encoded_token, "redirect_to" => redirect_to}) do
    # Token-based auto-login from account setup - skip CSRF protection
    token = Base.url_decode64!(encoded_token)

    if user = Accounts.get_user_by_session_token(token) do
      if user.state in [:pending_approval, :active] do
        # Log successful sign-in
        AuthService.log_login_success(user, conn, %{token: token})

        # Reset failed sign-in attempts and log in user
        conn
        |> delete_session(:failed_login_attempts)
        |> UserAuth.log_in_user(user, %{}, redirect_to)
      else
        # Account not active
        conn
        |> put_flash(:error, "Your account is not currently active.")
        |> redirect(to: ~p"/users/log-in")
      end
    else
      # Invalid token
      conn
      |> put_flash(:error, "Invalid login session.")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def auto_login(conn, %{"token" => encoded_token}) do
    # Token-based auto-login from account setup - skip CSRF protection
    token = Base.url_decode64!(encoded_token)

    if user = Accounts.get_user_by_session_token(token) do
      if user.state in [:pending_approval, :active] do
        # Log successful sign-in
        AuthService.log_login_success(user, conn, %{token: token})

        # Reset failed sign-in attempts and log in user
        # UserAuth.log_in_user will redirect to the appropriate path based on user state
        conn
        |> delete_session(:failed_login_attempts)
        |> UserAuth.log_in_user(user, %{})
      else
        # Account not active
        conn
        |> put_flash(:error, "Your account is not currently active.")
        |> redirect(to: ~p"/users/log-in")
      end
    else
      # Invalid token
      conn
      |> put_flash(:error, "Invalid login session.")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  defp create(conn, %{"user" => user_params} = params, info) do
    %{"email" => email, "password" => password} = user_params

    # Get redirect_to from form params (passed as hidden field from LiveView)
    # Also check session as fallback for backwards compatibility
    redirect_to =
      params["redirect_to"] ||
        get_session(conn, :user_return_to)

    if user = Accounts.get_user_by_email_and_password(email, password) do
      # Check if user's email is verified - if not, redirect to account setup
      if is_nil(user.email_verified_at) do
        conn
        |> put_flash(:info, "Please verify your email address before signing in.")
        |> redirect(to: ~p"/account/setup/#{user.id}")
      else
        # Check if user is in an allowed state for login
        if user.state in [:pending_approval, :active] do
          # Log successful sign-in
          AuthService.log_login_success(user, conn, user_params)

          # Reset failed sign-in attempts on successful sign-in
          # Validate redirect_to is internal before using it
          validated_redirect =
            if redirect_to && YscWeb.UserAuth.valid_internal_redirect?(redirect_to) do
              redirect_to
            else
              nil
            end

          conn
          |> put_flash(:info, info)
          |> delete_session(:failed_login_attempts)
          |> delete_session(:user_return_to)
          |> UserAuth.log_in_user(user, user_params, validated_redirect)
        else
          # Log failed sign-in attempt due to account state
          AuthService.log_login_failure(email, conn, "account_state_restriction", user_params)

          # Track failed sign-in attempts in session
          failed_attempts = (get_session(conn, :failed_login_attempts) || 0) + 1

          # Show error message explaining why login is not allowed
          conn
          |> put_flash(
            :error,
            "Your account is not currently active. Please contact info@ysc.org for more information."
          )
          |> put_flash(:email, String.slice(email, 0, 160))
          |> put_session(:failed_login_attempts, failed_attempts)
          |> redirect(to: ~p"/users/log-in")
        end
      end
    else
      # Log failed sign-in attempt
      AuthService.log_login_failure(email, conn, "invalid_credentials", user_params)

      # Track failed sign-in attempts in session
      failed_attempts = (get_session(conn, :failed_login_attempts) || 0) + 1

      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> put_session(:failed_login_attempts, failed_attempts)
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    # Log sign-out event if user is authenticated
    if current_user = conn.assigns[:current_user] do
      AuthService.log_logout(current_user, conn)
    end

    conn
    |> put_flash(:info, "Signed out successfully.")
    |> UserAuth.log_out_user()
  end
end
