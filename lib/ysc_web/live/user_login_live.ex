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
      <!-- Alternative Authentication Methods -->
      <div id="auth-methods" class="space-y-3 pt-8" phx-hook="DeviceDetection">
        <.button
          :if={@passkey_supported}
          type="button"
          class="w-full flex items-center justify-center gap-2 h-10"
          phx-click="sign_in_with_passkey"
          phx-mounted={
            JS.transition(
              {"transition ease-out duration-300", "opacity-0 -translate-y-1",
               "opacity-100 translate-y-0"}
            )
          }
        >
          <%= if @is_ios_mobile do %>
            <svg
              width="20"
              height="20"
              viewBox="0 0 80 80"
              version="1.1"
              xmlns="http://www.w3.org/2000/svg"
              class="w-5 h-5"
            >
              <g stroke="none" stroke-width="1" fill="currentColor" fill-rule="evenodd">
                <g>
                  <g id="Corners" fill-rule="nonzero">
                    <g id="Corner">
                      <path d="M4.11428571,21.9428571 L4.11428571,13.0285714 C4.11428571,7.99327149 7.99327149,4.11428571 13.0285714,4.11428571 L21.9428571,4.11428571 C23.0789858,4.11428571 24,3.19327149 24,2.05714286 C24,0.921014229 23.0789858,0 21.9428571,0 L13.0285714,0 C5.72101423,0 0,5.72101423 0,13.0285714 L0,21.9428571 C0,23.0789858 0.921014229,24 2.05714286,24 C3.19327149,24 4.11428571,23.0789858 4.11428571,21.9428571 Z">
                      </path>
                    </g>
                    <g
                      id="Corner"
                      transform="translate(68.070175, 11.929825) scale(-1, 1) translate(-68.070175, -11.929825) translate(56.140351, 0.000000)"
                    >
                      <path d="M4.11428571,21.9428571 L4.11428571,13.0285714 C4.11428571,7.99327149 7.99327149,4.11428571 13.0285714,4.11428571 L21.9428571,4.11428571 C23.0789858,4.11428571 24,3.19327149 24,2.05714286 C24,0.921014229 23.0789858,0 21.9428571,0 L13.0285714,0 C5.72101423,0 0,5.72101423 0,13.0285714 L0,21.9428571 C0,23.0789858 0.921014229,24 2.05714286,24 C3.19327149,24 4.11428571,23.0789858 4.11428571,21.9428571 Z">
                      </path>
                    </g>
                    <g
                      id="Corner"
                      transform="translate(11.929825, 68.070175) scale(1, -1) translate(-11.929825, -68.070175) translate(0.000000, 56.140351)"
                    >
                      <path d="M4.11428571,21.9428571 L4.11428571,13.0285714 C4.11428571,7.99327149 7.99327149,4.11428571 13.0285714,4.11428571 L21.9428571,4.11428571 C23.0789858,4.11428571 24,3.19327149 24,2.05714286 C24,0.921014229 23.0789858,0 21.9428571,0 L13.0285714,0 C5.72101423,0 0,5.72101423 0,13.0285714 L0,21.9428571 C0,23.0789858 0.921014229,24 2.05714286,24 C3.19327149,24 4.11428571,23.0789858 4.11428571,21.9428571 Z">
                      </path>
                    </g>
                    <g
                      id="Corner"
                      transform="translate(68.070175, 68.070175) scale(-1, -1) translate(-68.070175, -68.070175) translate(56.140351, 56.140351)"
                    >
                      <path d="M4.11428571,21.9428571 L4.11428571,13.0285714 C4.11428571,7.99327149 7.99327149,4.11428571 13.0285714,4.11428571 L21.9428571,4.11428571 C23.0789858,4.11428571 24,3.19327149 24,2.05714286 C24,0.921014229 23.0789858,0 21.9428571,0 L13.0285714,0 C5.72101423,0 0,5.72101423 0,13.0285714 L0,21.9428571 C0,23.0789858 0.921014229,24 2.05714286,24 C3.19327149,24 4.11428571,23.0789858 4.11428571,21.9428571 Z">
                      </path>
                    </g>
                  </g>
                  <g id="Eye" transform="translate(21.754386, 28.070175)" fill-rule="nonzero">
                    <path
                      d="M0,2.14285714 L0,7.86037654 C0,9.04384386 0.8954305,10.0032337 2,10.0032337 C3.1045695,10.0032337 4,9.04384386 4,7.86037654 L4,2.14285714 C4,0.959389822 3.1045695,0 2,0 C0.8954305,0 0,0.959389822 0,2.14285714 Z"
                      id="Path"
                    >
                    </path>
                  </g>
                  <g id="Eye" transform="translate(54.736842, 28.070175)" fill-rule="nonzero">
                    <path
                      d="M0,2.14285714 L0,7.86037654 C0,9.04384386 0.8954305,10.0032337 2,10.0032337 C3.1045695,10.0032337 4,9.04384386 4,7.86037654 L4,2.14285714 C4,0.959389822 3.1045695,0 2,0 C0.8954305,0 0,0.959389822 0,2.14285714 Z"
                      id="Path"
                    >
                    </path>
                  </g>
                  <path
                    d="M25.9319616,59.0829234 C29.8331111,62.7239962 34.5578726,64.5614035 40,64.5614035 C45.4421274,64.5614035 50.1668889,62.7239962 54.0680384,59.0829234 C54.9180398,58.2895887 54.9639773,56.9574016 54.1706427,56.1074002 C53.377308,55.2573988 52.0451209,55.2114613 51.1951195,56.0047959 C48.0787251,58.9134307 44.382434,60.3508772 40,60.3508772 C35.617566,60.3508772 31.9212749,58.9134307 28.8048805,56.0047959 C27.9548791,55.2114613 26.622692,55.2573988 25.8293573,56.1074002 C25.0360227,56.9574016 25.0819602,58.2895887 25.9319616,59.0829234 Z"
                    id="Mouth"
                    fill-rule="nonzero"
                  >
                  </path>
                  <path
                    d="M40,30.1754386 L40,44.9122807 C40,45.85537 39.539042,46.3157895 38.5912711,46.3157895 L37.1929825,46.3157895 C36.0302777,46.3157895 35.0877193,47.2583479 35.0877193,48.4210526 C35.0877193,49.5837574 36.0302777,50.5263158 37.1929825,50.5263158 L38.5912711,50.5263158 C41.8633505,50.5263158 44.2105263,48.1818819 44.2105263,44.9122807 L44.2105263,30.1754386 C44.2105263,29.0127339 43.2679679,28.0701754 42.1052632,28.0701754 C40.9425584,28.0701754 40,29.0127339 40,30.1754386 Z"
                    id="Nose"
                    fill-rule="nonzero"
                  >
                  </path>
                </g>
              </g>
            </svg>
          <% else %>
            <.icon name="hero-key" class="w-5 h-5" />
          <% end %>
          <%= if @is_ios_mobile do %>
            Sign in with Face ID (Passkey)
          <% else %>
            Sign in with Passkey
          <% end %>
        </.button>
        <.button
          type="button"
          variant="outline"
          class="w-full flex items-center justify-center gap-2 h-10"
          phx-click="sign_in_with_google"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            height="20"
            viewBox="0 0 24 24"
            width="20"
            class="w-5 h-5"
          >
            <path
              d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
              fill="#4285F4"
            />
            <path
              d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
              fill="#34A853"
            />
            <path
              d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
              fill="#FBBC05"
            />
            <path
              d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
              fill="#EA4335"
            />
            <path d="M1 1h22v22H1z" fill="none" />
          </svg>
          Sign in with Google
        </.button>
        <.button
          type="button"
          variant="outline"
          class="w-full flex items-center justify-center gap-2 h-10"
          phx-click="sign_in_with_facebook"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            height="20"
            viewBox="0 0 24 24"
            width="20"
            class="w-5 h-5"
          >
            <path
              d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"
              fill="#1877F2"
            />
          </svg>
          Sign in with Facebook
        </.button>
      </div>
      <!-- Divider -->
      <div class="relative my-6">
        <div class="absolute inset-0 flex items-center">
          <div class="w-full border-t border-zinc-300"></div>
        </div>
        <div class="relative flex justify-center items-center text-sm leading-none">
          <span class="bg-white px-2 text-zinc-500">or</span>
        </div>
      </div>
      <!-- Failed Sign-in Attempts Banner -->
      <div
        :if={@failed_login_attempts >= 3 && !@banner_dismissed}
        id="failed-login-banner"
        class="bg-amber-50 border border-amber-200 rounded-lg p-4 my-6 relative"
        phx-mounted={
          JS.transition(
            {"transition ease-out duration-300", "opacity-0 -translate-y-1",
             "opacity-100 translate-y-0"}
          )
        }
        phx-remove={JS.transition({"transition ease-in duration-200", "opacity-100", "opacity-0"})}
      >
        <button
          type="button"
          phx-click="dismiss_banner"
          class="absolute top-2 right-2 p-1 rounded hover:bg-amber-100 opacity-60 hover:opacity-100 transition-opacity"
          aria-label="Dismiss"
        >
          <.icon name="hero-x-mark" class="w-5 h-5 text-amber-600" />
        </button>
        <div class="flex items-start pr-6">
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

      <.simple_form for={@form} id="login_form" action={~p"/users/log-in"} phx-update="ignore">
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
     |> assign(:redirect_to, redirect_to)
     |> assign(:is_ios_mobile, false)
     |> assign(:passkey_supported, false)
     |> assign(:banner_dismissed, false), temporary_assigns: [form: form]}
  end

  def handle_event("sign_in_with_passkey", _params, socket) do
    # Placeholder for passkey authentication
    {:noreply, put_flash(socket, :info, "Passkey authentication coming soon!")}
  end

  def handle_event("sign_in_with_google", _params, socket) do
    # Pass redirect_to as query parameter - Ueberauth will preserve it through OAuth flow
    redirect_to = socket.assigns.redirect_to

    oauth_url =
      if redirect_to && YscWeb.UserAuth.valid_internal_redirect?(redirect_to) do
        ~p"/auth/google?redirect_to=#{URI.encode(redirect_to)}"
      else
        ~p"/auth/google"
      end

    # Redirect to OAuth provider (full page redirect, not LiveView navigation)
    {:noreply, socket |> redirect(to: oauth_url)}
  end

  def handle_event("sign_in_with_facebook", _params, socket) do
    # Pass redirect_to as query parameter - Ueberauth will preserve it through OAuth flow
    redirect_to = socket.assigns.redirect_to

    oauth_url =
      if redirect_to && YscWeb.UserAuth.valid_internal_redirect?(redirect_to) do
        ~p"/auth/facebook?redirect_to=#{URI.encode(redirect_to)}"
      else
        ~p"/auth/facebook"
      end

    # Redirect to OAuth provider (full page redirect, not LiveView navigation)
    {:noreply, socket |> redirect(to: oauth_url)}
  end

  def handle_event("device_detected", %{"device" => "ios_mobile"}, socket) do
    {:noreply, assign(socket, :is_ios_mobile, true)}
  end

  def handle_event("device_detected", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("passkey_support_detected", %{"supported" => supported}, socket) do
    {:noreply, assign(socket, :passkey_supported, supported)}
  end

  def handle_event("passkey_support_detected", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("dismiss_banner", _params, socket) do
    # Reset failed login attempts when user dismisses the banner
    # Redirect to controller endpoint to clear session, then redirect back
    {:noreply,
     socket
     |> assign(:failed_login_attempts, 0)
     |> assign(:banner_dismissed, true)
     |> redirect(to: ~p"/users/log-in/reset-attempts")}
  end
end
