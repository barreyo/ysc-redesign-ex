defmodule YscWeb.UserLoginLive do
  use YscWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="max-w-sm mx-auto py-10">
      <.link
        navigate={~p"/"}
        class="flex items-center text-center justify-center py-10 hover:opacity-80 transition duration-200 ease-in-out"
      >
        <.ysc_logo class="h-20" />
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

  def mount(_params, _session, socket) do
    email = live_flash(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form) |> assign(:page_title, "Login"), temporary_assigns: [form: form]}
  end
end
