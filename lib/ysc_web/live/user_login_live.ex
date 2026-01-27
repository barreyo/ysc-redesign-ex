defmodule YscWeb.UserLoginLive do
  use YscWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="max-w-sm mx-auto py-10">
      <.link
        navigate={~p"/"}
        class="flex items-center text-center justify-center py-10 hover:opacity-80 transition duration-200 ease-in-out"
      >
        <.ysc_logo class="h-28" />
      </.link>
      <.header class="text-center">
        Sign in to your YSC account
        <:subtitle>
          Not a member yet?
          <.link navigate={~p"/users/register"} class="font-semibold text-blue-600 hover:underline">
            Apply for a membership
          </.link>
        </:subtitle>
      </.header>
      <!-- Failed Sign-in Attempts Banner -->
      <div
        :if={@failed_login_attempts >= 3}
        class="bg-amber-50 border border-amber-200 rounded-lg p-4 my-6"
      >
        <div class="flex items-start">
          <div class="flex-shrink-0">
            <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-amber-600" />
          </div>
          <div class="ml-3 flex-1">
            <h3 class="text-sm font-semibold text-amber-900">Having trouble signing in?</h3>
            <div class="mt-2 text-sm text-amber-800">
              <p class="mb-2">
                You've had multiple failed sign-in attempts. You may want to reset your password.
              </p>
              <div class="flex flex-col sm:flex-row gap-2">
                <.link
                  navigate={~p"/users/reset-password"}
                  class="font-semibold text-amber-900 hover:text-amber-950 underline"
                >
                  Reset your password
                </.link>
                <span class="hidden sm:inline">•</span>
                <.link
                  href="mailto:info@ysc.org"
                  class="font-semibold text-amber-900 hover:text-amber-950 underline"
                >
                  Contact us for help
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Alternative Authentication Methods -->
      <div class="space-y-3 pt-8">
        <.button
          type="button"
          variant="outline"
          class="w-full flex items-center justify-center gap-2"
          phx-click="sign_in_with_passkey"
        >
          <.icon name="hero-fingerprint" class="w-5 h-5" />
          Sign in with Passkey
        </.button>
        <.button
          type="button"
          variant="outline"
          class="w-full flex items-center justify-center gap-2"
          phx-click="sign_in_with_google"
        >
          <svg xmlns="http://www.w3.org/2000/svg" height="20" viewBox="0 0 24 24" width="20" class="w-5 h-5">
            <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/>
            <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
            <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
            <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
            <path d="M1 1h22v22H1z" fill="none"/>
          </svg>
          Sign in with Google
        </.button>
      </div>

      <!-- Divider -->
      <div class="relative my-6">
        <div class="absolute inset-0 flex items-center">
          <div class="w-full border-t border-zinc-300"></div>
        </div>
        <div class="relative flex justify-center text-sm">
          <span class="bg-white px-2 text-zinc-500">or</span>
        </div>
      </div>

      <.simple_form
        for={@form}
        id="login_form"
        action={~p"/users/log-in"}
        phx-update="ignore"
      >
        <input type="hidden" name="redirect_to" value={@redirect_to} />
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:password]} type="password-toggle" label="Password" required />

        <:actions>
          <.input field={@form[:remember_me]} type="checkbox" label="Keep me signed in" />
          <.link
            href={~p"/users/reset-password"}
            class="text-sm font-semibold hover:underline text-blue-600"
          >
            Forgot your password?
          </.link>
        </:actions>
        <:actions>
          <.button phx-disable-with="Signing in..." class="w-full">
            Sign in <.icon name="hero-arrow-right" class="w-5 h-5 ms-1 -mt-0.5" />
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def mount(params, session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    # Get failed login attempts from session (handle both atom and string keys)
    failed_login_attempts =
      session
      |> Map.get(:failed_login_attempts)
      |> Kernel.||(Map.get(session, "failed_login_attempts"))
      |> Kernel.||(0)

    # Capture redirect_to from URL params and validate it's an internal path
    redirect_to =
      case params do
        %{"redirect_to" => redirect_path} when is_binary(redirect_path) ->
          if YscWeb.UserAuth.valid_internal_redirect?(redirect_path) do
            redirect_path
          else
            nil
          end

        _ ->
          nil
      end

    {:ok,
     assign(socket, form: form)
     |> assign(:page_title, "Sign in")
     |> assign(:failed_login_attempts, failed_login_attempts)
     |> assign(:redirect_to, redirect_to), temporary_assigns: [form: form]}
  end

  def handle_event("sign_in_with_passkey", _params, socket) do
    # Placeholder for passkey authentication
    {:noreply, put_flash(socket, :info, "Passkey authentication coming soon!")}
  end

  def handle_event("sign_in_with_google", _params, socket) do
    # Placeholder for Google OAuth authentication
    {:noreply, put_flash(socket, :info, "Google authentication coming soon!")}
  end
end
