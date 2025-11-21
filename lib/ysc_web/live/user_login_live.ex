defmodule YscWeb.UserLoginLive do
  use YscWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="max-w-sm mx-auto py-10">
      <.link
        navigate={~p"/"}
        class="flex items-center text-center justify-center py-10 hover:opacity-80 transition duration-200 ease-in-out"
      >
        <.ysc_logo class="h-24" />
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
                  href={~p"/users/reset-password"}
                  class="font-semibold text-amber-900 hover:text-amber-950 underline"
                >
                  Reset your password
                </.link>
                <span class="hidden sm:inline">•</span>
                <a
                  href="mailto:info@ysc.org"
                  class="font-semibold text-amber-900 hover:text-amber-950 underline"
                >
                  Contact us for help
                </a>
              </div>
            </div>
          </div>
        </div>
      </div>

      <.simple_form for={@form} id="login_form" action={~p"/users/log-in"} phx-update="ignore">
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:password]} type="password" label="Password" required />

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
            Sign in <span aria-hidden="true">→</span>
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def mount(_params, session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    # Get failed login attempts from session (handle both atom and string keys)
    failed_login_attempts =
      session
      |> Map.get(:failed_login_attempts)
      |> Kernel.||(Map.get(session, "failed_login_attempts"))
      |> Kernel.||(0)

    {:ok,
     assign(socket, form: form)
     |> assign(:page_title, "Sign in")
     |> assign(:failed_login_attempts, failed_login_attempts), temporary_assigns: [form: form]}
  end
end
