defmodule YscWeb.AccountSetupLive do
  use YscWeb, :live_view

  alias Ysc.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-xl mx-auto py-10">
      <div class="flex w-full mx-auto items-center text-center justify-center">
        <.link navigate={~p"/"} class="p-10 hover:opacity-80 transition duration-200 ease-in-out">
          <.ysc_logo class="h-28" />
        </.link>
      </div>

      <div
        :if={
          length(build_stepper_steps(@skip_password, @skip_phone_setup, @skip_phone_verification)) > 1
        }
        class="w-full px-2"
      >
        <.stepper
          active_step={
            stepper_active_step(
              @current_step,
              @skip_password,
              @skip_phone_setup,
              @skip_phone_verification
            )
          }
          steps={build_stepper_steps(@skip_password, @skip_phone_setup, @skip_phone_verification)}
        />
      </div>

      <div class="px-2 py-8">
        <div :if={@current_step === 0}>
          <.alert_box :if={@from_signup}>
            <.icon name="hero-rocket-launch" class="w-12 h-12 text-blue-800 me-3 mt-1" />
            Your application is submitted and is currently being reviewed by the board. We will email you as soon as your membership is approved..<br /><br />
            While you wait, let's finish setting up your account!
          </.alert_box>

          <.header class="text-left">
            Verify Your Email Address
            <:subtitle>
              We sent a verification code to <strong><%= @user.email %></strong>. Please enter it below to continue.
            </:subtitle>
          </.header>

          <.simple_form
            for={@email_form}
            id="email_form"
            phx-submit="verify_code"
            phx-change="validate_email_code"
          >
            <.input
              field={@email_form[:verification_code]}
              type="otp"
              label="Verification Code"
              required
            />
            <p class="text-xs text-zinc-600 mt-1">
              Didn't receive the code? Check your spam folder or <.link
                phx-click="resend_code"
                class="text-blue-600 hover:underline cursor-pointer"
              >
                click here to resend
              </.link>.
            </p>

            <:actions>
              <.button phx-disable-with="Verifying..." type="submit">Verify Code</.button>
            </:actions>
          </.simple_form>
        </div>

        <div :if={@current_step === 1 and not @skip_password}>
          <.header class="text-left">
            Set Your Password
            <:subtitle>
              Create a password to access your account and manage your membership.
            </:subtitle>
          </.header>

          <.simple_form
            for={@password_form}
            id="password_form"
            phx-submit="save_password"
            phx-change="validate_password"
          >
            <.input
              field={@password_form[:password]}
              type="password-toggle"
              label="Password"
              required
              placeholder="Enter a secure password"
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password-toggle"
              label="Confirm Password"
              required
              placeholder="Confirm your password"
            />

            <:actions>
              <.button phx-disable-with="Setting password...">Set Password</.button>
            </:actions>
          </.simple_form>
        </div>

        <div :if={@current_step === 2 and not @skip_phone_setup}>
          <.header class="text-left">
            Add Your Phone Number (Optional)
            <:subtitle>
              Providing your phone number allows us to send you SMS notifications for important account updates and event reminders.
            </:subtitle>
          </.header>

          <.simple_form
            for={@phone_form}
            id="phone_form"
            phx-submit="save_phone"
            phx-change="validate_phone"
          >
            <.input type="phone-input" label="Phone Number" field={@phone_form[:phone_number]} />
            <.input
              type="checkbox"
              label="I would like to receive SMS notifications for account security, event reminders, and booking updates"
              field={@phone_form[:sms_opt_in]}
            />
            <p class="text-xs text-zinc-600 mt-1">
              <strong>Young Scandinavians Club (YSC)</strong>: By voluntarily providing your phone number and explicitly opting in to text messaging, you agree to receive account security codes and booking reminders from Young Scandinavians Club(YSC). Message frequency may vary. Message & data rates may apply. Reply HELP for support or STOP to unsubscribe. Your phone number will not be shared with third parties for marketing or promotional purposes. You can also opt out at any time in your notification settings. See our
              <.link navigate={~p"/privacy-policy"} class="text-blue-600 hover:underline">
                Privacy Policy
              </.link>
              for more information.
            </p>

            <:actions>
              <.button class="bg-zinc-200 text-zinc-800 hover:bg-zinc-300" phx-click="skip_phone">
                Skip for now
              </.button>
              <.button phx-disable-with="Saving...">Save Phone Number</.button>
            </:actions>
          </.simple_form>
        </div>

        <div :if={@current_step === 3 and not @skip_phone_verification}>
          <.header class="text-left">
            Verify Your Phone Number
            <:subtitle>
              We sent a verification code to <strong><%= @user.phone_number %></strong>. Please enter it below to continue.
            </:subtitle>
          </.header>

          <.simple_form
            for={@phone_verification_form}
            id="phone_verification_form"
            phx-submit="verify_phone_code"
            phx-change="validate_phone_code"
          >
            <p
              :if={dev_or_sandbox?()}
              class="text-xs text-amber-600 mt-2 bg-amber-50 p-2 rounded border border-amber-200"
            >
              <strong>Dev Mode:</strong>
              You can use <code class="bg-amber-100 px-1 rounded">000000</code>
              as the verification code.
            </p>
            <.input
              field={@phone_verification_form[:verification_code]}
              type="otp"
              label="Verification Code"
              required
            />
            <p class="text-xs text-zinc-600 mt-1">
              Didn't receive the code? Check your messages or <.link
                phx-click="resend_phone_code"
                class="text-blue-600 hover:underline cursor-pointer"
              >
                click here to resend
              </.link>.
            </p>

            <div class="py-2">
              <p class="text-sm mb-2 text-zinc-600 font-bold">
                Want to use a different phone number?
              </p>
              <button
                type="button"
                phx-click="change_phone_number"
                class="text-sm text-blue-600 hover:text-blue-700 font-medium hover:underline"
              >
                Change phone number →
              </button>
            </div>

            <:actions>
              <div class="flex justify-end w-full">
                <.button phx-disable-with="Verifying...">
                  <.icon name="hero-check-circle" class="w-5 h-5 me-1 -mt-0.5" />Verify Phone Number
                </.button>
              </div>
            </:actions>
          </.simple_form>
        </div>

        <div :if={@current_step === 4 && !@trigger_login}>
          <.header class="text-left">
            Account Setup Complete!
            <:subtitle>
              Welcome to the Young Scandinavians Club! You can now access all features.
            </:subtitle>
          </.header>

          <div class="text-center py-8">
            <.icon name="hero-check-circle" class="w-16 h-16 text-green-600 mx-auto mb-4" />
            <p class="text-zinc-600 mb-4">
              Your account has been successfully set up and you're now logged in.
            </p>
            <.link
              href={~p"/"}
              class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
            >
              Continue to Dashboard
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Build stepper steps dynamically - only show steps that are actually needed
  # Email verification OR password setup (never both, never phone)
  # Build stepper steps dynamically based on which steps are skipped
  # Email verification, password setup, and/or phone verification
  defp build_stepper_steps(skip_password, _skip_phone_setup, skip_phone_verification) do
    steps = ["Email"]

    # Add password step if not skipped
    steps = if not skip_password, do: steps ++ ["Password"], else: steps

    # Add phone step if phone verification is needed
    steps = if not skip_phone_verification, do: steps ++ ["Phone & Verification"], else: steps

    steps
  end

  # Helper function to map current_step to stepper display step
  # Simplified: only Email (step 0) or Email + Password (steps 0, 1)
  defp stepper_active_step(
         current_step,
         skip_password,
         _skip_phone_setup,
         skip_phone_verification
       ) do
    case current_step do
      # Email verification - always step 0
      0 ->
        0

      # Password setup - position depends on what comes before
      1 ->
        1

      # Phone setup - position depends on what was skipped
      2 ->
        if skip_password, do: 1, else: 2

      # Phone verification - combined with setup visually
      3 ->
        if skip_password, do: 1, else: 2

      # Complete - final step position
      4 ->
        cond do
          # Only email
          skip_password and skip_phone_verification -> 1
          # Email + one more
          skip_password or skip_phone_verification -> 2
          # All three
          true -> 3
        end

      # Default
      _ ->
        0
    end
  end

  # Helper function to check if we're in dev/sandbox mode
  defp dev_or_sandbox? do
    Mix.env() in [:dev, :test]
  end

  @impl true
  def mount(%{"user_id" => user_id}, _session, socket) do
    user = Accounts.get_user!(user_id)
    current_user = socket.assigns.current_user

    # Determine if user needs account setup
    # User needs setup if: email not verified OR password not set OR phone not verified
    needs_account_setup =
      is_nil(user.email_verified_at) or is_nil(user.password_set_at) or
        is_nil(user.phone_verified_at)

    is_own_setup = !!(current_user && current_user.id == user.id)

    # Check authentication requirements based on user's progress
    can_access =
      cond do
        # User doesn't need account setup: deny access
        not needs_account_setup ->
          false

        # Email not verified: allow anyone (initial access)
        is_nil(user.email_verified_at) ->
          true

        # Email verified but password not set: require authentication
        is_nil(user.password_set_at) ->
          is_own_setup

        # Password set but phone not verified: require authentication
        is_nil(user.phone_verified_at) ->
          is_own_setup

        # Default: deny access
        true ->
          false
      end

    if not can_access do
      {:ok,
       socket
       |> put_flash(:error, "Your account setup is already complete.")
       |> redirect(to: ~p"/")}
    else
      # Check if user came from signup form
      from_signup =
        socket |> Phoenix.LiveView.get_connect_params() |> get_in(["from_signup"]) == "true"

      # Determine which steps to skip based on user's existing data
      skip_password = not is_nil(user.password_set_at)
      skip_phone_setup = not is_nil(user.phone_number)
      skip_phone_verification = not is_nil(user.phone_verified_at)

      # Create phone changeset with existing phone number if available
      phone_changeset =
        if not is_nil(user.phone_number) do
          # Pre-fill with existing phone number
          Ysc.Accounts.User.registration_changeset(user, %{"phone_number" => user.phone_number},
            hash_password: false,
            validate_email: false
          )
        else
          Ysc.Accounts.User.registration_changeset(user, %{},
            hash_password: false,
            validate_email: false
          )
        end

      phone_verification_changeset = %{"verification_code" => ""} |> to_form()

      # Determine starting step based on user's progress and authentication
      starting_step =
        cond do
          # Email verification needed (unauthenticated access allowed)
          is_nil(user.email_verified_at) ->
            0

          # Email verified and authenticated, but password not set
          is_own_setup and not is_nil(user.email_verified_at) and is_nil(user.password_set_at) ->
            1

          # Password set but phone not verified
          is_own_setup and not is_nil(user.password_set_at) and is_nil(user.phone_verified_at) ->
            cond do
              # Need to set up phone
              is_nil(user.phone_number) -> 2
              # Have phone but need verification
              not is_nil(user.phone_number) -> 3
            end

          # All required steps complete
          true ->
            4
        end

      # Start at the appropriate step based on authentication
      # handle_params will handle URL parameter updates
      current_step = starting_step
      password_changeset = Accounts.change_user_password(user)

      # Generate and send initial verification code only if one doesn't already exist
      case Ysc.VerificationCache.get_code(user.id, :email_verification) do
        {:ok, _existing_code} ->
          # Code already exists, don't generate a new one
          :ok

        {:error, _} ->
          # No existing code, generate and send new one
          code = Accounts.generate_and_store_email_verification_code(user)
          _job = Accounts.send_email_verification_code(user, code, "initial")
      end

      email_changeset = %{"verification_code" => ""} |> to_form()

      # Start at step 0 - user progresses through the flow

      socket =
        socket
        |> assign(:page_title, "Complete Your Account Setup")
        |> assign(:user, user)
        |> assign(:current_step, current_step)
        |> assign(:email_verified, false)
        |> assign(:from_signup, from_signup)
        |> assign(:skip_password, skip_password)
        |> assign(:skip_phone_setup, skip_phone_setup)
        |> assign(:skip_phone_verification, skip_phone_verification)
        |> assign(:trigger_login, false)
        |> assign(:email_form, email_changeset)
        |> assign(:password_form, to_form(password_changeset))
        |> assign(:phone_form, to_form(phone_changeset))
        |> assign(:phone_verification_form, phone_verification_changeset)

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    # Handle step parameter from URL query string
    step_param =
      case uri do
        %URI{query: query} when query != nil ->
          URI.decode_query(query)["step"]

        _ ->
          nil
      end

    if step_param do
      requested_step = String.to_integer(step_param)
      current_user = socket.assigns.current_user
      user = socket.assigns.user

      # Check authentication for steps that require it
      can_access_step =
        cond do
          requested_step == 0 ->
            # Email verification step: always accessible
            true

          requested_step > 0 and is_nil(user.email_verified_at) ->
            # Trying to access steps after email verification but email not verified
            false

          requested_step > 0 and current_user != user ->
            # Trying to access authenticated steps but not the owner
            false

          true ->
            # Authenticated owner accessing their own setup
            true
        end

      if not can_access_step do
        {:noreply,
         socket
         |> put_flash(:error, "Please verify your email first to continue account setup.")
         |> redirect(to: ~p"/users/log-in")}
      else
        # Re-fetch user to get latest data for access control
        fresh_user = Accounts.get_user!(user.id)
        skip_password = socket.assigns.skip_password
        skip_phone_verification = socket.assigns.skip_phone_verification

        has_verified_email = not is_nil(fresh_user.email_verified_at)
        has_set_password = not is_nil(fresh_user.password_set_at)
        has_verified_phone = not is_nil(fresh_user.phone_verified_at)

        # Calculate allowed step based on user's progress
        allowed_step =
          cond do
            # Users who haven't verified email can only access step 0
            !has_verified_email ->
              0

            # Users who have verified email but haven't set password can access step 1
            has_verified_email and not has_set_password and not skip_password ->
              min(requested_step, 1)

            # Users who have set password but haven't verified phone can access phone steps
            has_verified_email and has_set_password and not has_verified_phone and
                not skip_phone_verification ->
              cond do
                # Can access verification
                not is_nil(fresh_user.phone_number) -> min(requested_step, 3)
                # Can access setup
                true -> min(requested_step, 2)
              end

            # All required steps complete
            true ->
              4
          end

        # Automatically send phone verification code if user reaches step 3 with unverified phone
        socket =
          if allowed_step == 3 and not is_nil(fresh_user.phone_number) and
               is_nil(fresh_user.phone_verified_at) do
            # Check if code already exists in cache
            case Ysc.VerificationCache.get_code(fresh_user.id, :phone_verification) do
              {:ok, _existing_code} ->
                # Code already exists, don't send new one
                socket

              {:error, _} ->
                # Generate and send new verification code
                phone_code = Accounts.generate_and_store_phone_verification_code(fresh_user)
                _job = Accounts.send_phone_verification_code(fresh_user, phone_code, "auto_step3")
                socket
            end
          else
            socket
          end

        {:noreply, assign(socket, :current_step, allowed_step)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate_email_code", %{"verification_code" => code}, socket) do
    # Handle both OTP array format and single string format
    normalized_code = normalize_verification_code(code)
    # Basic validation - ensure it's 6 digits
    is_valid = String.length(normalized_code) == 6 && String.match?(normalized_code, ~r/^\d{6}$/)
    {:noreply, assign(socket, :code_valid, is_valid)}
  end

  def handle_event("verify_code", %{"verification_code" => entered_code}, socket) do
    # Handle both OTP array format and single string format
    code = normalize_verification_code(entered_code)

    case Accounts.verify_email_verification_code(socket.assigns.user, code) do
      {:ok, :verified} ->
        # Mark email as verified in database
        {:ok, updated_user} = Accounts.mark_email_verified(socket.assigns.user)

        # Determine next step, skipping password if already set
        next_step = if not is_nil(updated_user.password_set_at), do: 4, else: 1

        # Create session token and log the user in
        token = Accounts.generate_user_session_token(updated_user)

        # Redirect to auto-login to establish session, then back to account setup
        {:noreply,
         socket
         |> Phoenix.LiveView.redirect(
           to:
             ~p"/users/log-in/auto?#{%{token: Base.url_encode64(token), redirect_to: "/account/setup/#{updated_user.id}?step=#{next_step}"}}"
         )}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "No verification code found. Please request a new one.")}

      {:error, :expired} ->
        {:noreply,
         socket
         |> put_flash(:error, "Verification code has expired. Please request a new one.")}

      {:error, :invalid_code} ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid verification code. Please try again.")}
    end
  end

  def handle_event("resend_code", _params, socket) do
    # Get existing code or generate new one
    {code, is_existing} =
      case Ysc.VerificationCache.get_code(socket.assigns.user.id, :email_verification) do
        {:ok, existing_code} ->
          {existing_code, true}

        {:error, _} ->
          # Generate new code if none exists
          new_code = Accounts.generate_and_store_email_verification_code(socket.assigns.user)
          {new_code, false}
      end

    # Use timestamp to make idempotency key unique for resend attempts
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    suffix = if is_existing, do: "resend_existing_#{timestamp}", else: "resend_new_#{timestamp}"
    _job = Accounts.send_email_verification_code(socket.assigns.user, code, suffix)

    {:noreply,
     socket
     |> put_flash(:info, "A new verification code has been sent to your email.")}
  end

  def handle_event("validate_password", %{"user" => user_params}, socket) do
    # Only allow password validation if email has been verified
    if socket.assigns.current_step >= 1 and not is_nil(socket.assigns.user.email_verified_at) do
      password_form =
        socket.assigns.user
        |> Accounts.change_user_password(user_params)
        |> Map.put(:action, :validate)
        |> to_form()

      {:noreply, assign(socket, password_form: password_form)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate_phone", %{"user" => user_params}, socket) do
    # Only allow phone validation if user is on phone setup step
    if socket.assigns.current_step >= 2 and not socket.assigns.skip_phone_setup do
      phone_form =
        socket.assigns.user
        |> Accounts.User.registration_changeset(user_params,
          hash_password: false,
          validate_email: false
        )
        |> Map.put(:action, :validate)
        |> to_form()

      {:noreply, assign(socket, phone_form: phone_form)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("change_phone_number", _params, socket) do
    # Allow user to change phone number by going back to step 2
    # Reset skip_phone_setup to false so they can modify their phone
    {:noreply,
     socket
     |> assign(:current_step, 2)
     |> assign(:skip_phone_setup, false)
     |> push_patch(to: ~p"/account/setup/#{socket.assigns.user.id}?step=2")}
  end

  def handle_event("save_password", %{"user" => user_params}, socket) do
    # Ensure email has been verified
    if socket.assigns.current_step < 1 or is_nil(socket.assigns.user.email_verified_at) do
      {:noreply,
       socket
       |> put_flash(:error, "Please verify your email address first.")}
    else
      case Accounts.set_user_initial_password(socket.assigns.user, user_params) do
        {:ok, updated_user} ->
          # Store the password for later login and move to next step
          password = user_params["password"]

          # Cache the password temporarily for the account setup flow
          cache_key = "account_setup_password:#{updated_user.id}"
          Cachex.put(:ysc_cache, cache_key, password, ttl: :timer.minutes(30))

          # Determine next step based on phone verification status
          next_step =
            cond do
              # Phone already verified, go to complete
              not is_nil(updated_user.phone_verified_at) -> 4
              # Phone set but not verified, go to verification
              not is_nil(updated_user.phone_number) -> 3
              # Need to set up phone first
              true -> 2
            end

          {:noreply,
           socket
           |> assign(:current_step, next_step)
           |> push_patch(to: ~p"/account/setup/#{socket.assigns.user.id}?step=#{next_step}")
           |> assign(:user, updated_user)
           |> assign(:password, password)
           |> put_flash(:info, "Password set successfully!")}

        {:error, changeset} ->
          {:noreply, assign(socket, password_form: to_form(changeset))}
      end
    end
  end

  def handle_event("save_phone", %{"user" => user_params}, socket) do
    # Ensure password has been set - re-fetch user to get latest data
    user = Accounts.get_user!(socket.assigns.user.id)

    if socket.assigns.current_step < 2 or is_nil(user.password_set_at) do
      {:noreply,
       socket
       |> put_flash(:error, "Please set your password first.")}
    else
      case Accounts.update_user_phone_and_sms(user, user_params) do
        {:ok, updated_user} ->
          # Generate and send phone verification code
          phone_code = Accounts.generate_and_store_phone_verification_code(updated_user)
          _job = Accounts.send_phone_verification_code(updated_user, phone_code, "initial")

          # Advance to phone verification step
          {:noreply,
           socket
           |> assign(:current_step, 3)
           |> assign(:user, updated_user)
           |> push_patch(to: ~p"/account/setup/#{socket.assigns.user.id}?step=3")
           |> put_flash(:info, "Phone number saved! Please verify it with the code we sent.")}

        {:error, changeset} ->
          {:noreply, assign(socket, phone_form: to_form(changeset))}
      end
    end
  end

  def handle_event("skip_phone", _params, socket) do
    # Ensure user has completed password setup - re-fetch user to get latest data
    user = Accounts.get_user!(socket.assigns.user.id)

    if is_nil(user.password_set_at) do
      {:noreply,
       socket
       |> put_flash(:error, "Please complete account setup first.")}
    else
      # After skipping phone setup, complete account setup
      # Generate session token and redirect for auto-login
      token = Accounts.generate_user_session_token(user)

      {:noreply,
       socket
       |> Phoenix.LiveView.redirect(
         to: ~p"/users/log-in/auto?#{%{token: Base.url_encode64(token)}}"
       )}
    end
  end

  def handle_event("set-step", %{"step" => step_str}, socket) do
    requested_step = String.to_integer(step_str)
    _current_step = socket.assigns.current_step

    # Check if step is accessible based on progress
    can_access_step =
      cond do
        requested_step == 0 ->
          # Email verification step: always accessible
          true

        requested_step > 0 and is_nil(socket.assigns.user.email_verified_at) ->
          # Trying to access steps after email verification but email not verified
          false

        true ->
          # Other steps: accessible if user is authenticated (which mount ensures)
          true
      end

    if not can_access_step do
      {:noreply,
       socket
       |> put_flash(:error, "Please verify your email first to continue account setup.")
       |> redirect(to: ~p"/account/setup/#{socket.assigns.user.id}")}
    else
      # Re-fetch user to get latest data for step validation
      fresh_user = Accounts.get_user!(socket.assigns.user.id)
      skip_password = socket.assigns.skip_password
      skip_phone = socket.assigns.skip_phone

      # Calculate the maximum allowed step based on progress
      max_allowed_step =
        cond do
          is_nil(fresh_user.email_verified_at) ->
            0

          not is_nil(fresh_user.email_verified_at) and
              (is_nil(fresh_user.password_set_at) and not skip_password) ->
            1

          not is_nil(fresh_user.password_set_at) or skip_password ->
            cond do
              is_nil(fresh_user.phone_number) and not skip_phone ->
                2

              not is_nil(fresh_user.phone_number) or skip_phone ->
                if is_nil(fresh_user.phone_verified_at) and not skip_phone, do: 3, else: 4

              true ->
                4
            end

          true ->
            0
        end

      allowed_step = min(requested_step, max_allowed_step)

      if requested_step > max_allowed_step do
        # Trying to jump ahead - show error message
        {:noreply,
         socket
         |> put_flash(:error, "Please complete the current step before proceeding.")}
      else
        # Allow navigation to completed or current step
        {:noreply, assign(socket, :current_step, allowed_step)}
      end
    end
  end

  def handle_event("validate_phone_code", %{"verification_code" => code}, socket) do
    # Handle both OTP array format and single string format
    normalized_code = normalize_verification_code(code)
    # Basic validation - ensure it's 6 digits
    is_valid = String.length(normalized_code) == 6 && String.match?(normalized_code, ~r/^\d{6}$/)
    {:noreply, assign(socket, phone_code_valid: is_valid)}
  end

  def handle_event("verify_phone_code", %{"verification_code" => entered_code}, socket) do
    # Ensure user has phone setup - re-fetch user to get latest data
    user = Accounts.get_user!(socket.assigns.user.id)

    if is_nil(user.phone_number) do
      {:noreply,
       socket
       |> put_flash(:error, "Please complete phone setup first.")}
    else
      # Handle both OTP array format and single string format
      code = normalize_verification_code(entered_code)

      case Accounts.verify_phone_verification_code(user, code) do
        {:ok, :verified} ->
          # Mark phone as verified in database
          {:ok, updated_user} = Accounts.mark_phone_verified(user)

          # Generate session token and redirect based on account state
          token = Accounts.generate_user_session_token(updated_user)

          {:noreply,
           socket
           |> Phoenix.LiveView.redirect(
             to: ~p"/users/log-in/auto?#{%{token: Base.url_encode64(token)}}"
           )}

        {:error, :not_found} ->
          {:noreply,
           socket
           |> put_flash(:error, "No verification code found. Please request a new one.")}

        {:error, :expired} ->
          {:noreply,
           socket
           |> put_flash(:error, "Verification code has expired. Please request a new one.")}

        {:error, :invalid_code} ->
          {:noreply,
           socket
           |> put_flash(:error, "Invalid verification code. Please try again.")}
      end
    end
  end

  def handle_event("resend_phone_code", _params, socket) do
    # Ensure user has phone setup - re-fetch user to get latest data
    user = Accounts.get_user!(socket.assigns.user.id)

    if is_nil(user.phone_number) do
      {:noreply,
       socket
       |> put_flash(:error, "Please complete phone setup first.")}
    else
      # Get existing code or generate new one
      {code, is_existing} =
        case Ysc.VerificationCache.get_code(user.id, :phone_verification) do
          {:ok, existing_code} ->
            {existing_code, true}

          {:error, _} ->
            # Generate new code if none exists
            new_code = Accounts.generate_and_store_phone_verification_code(user)
            {new_code, false}
        end

      # Send the code via SMS
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      suffix = if is_existing, do: "resend_existing_#{timestamp}", else: "resend_new_#{timestamp}"
      _job = Accounts.send_phone_verification_code(user, code, suffix)

      {:noreply,
       socket
       |> put_flash(:info, "Verification code sent to your phone.")}
    end
  end

  # Helper function to normalize verification code from OTP array/map or string format
  defp normalize_verification_code(code) when is_map(code) do
    # Handle map format: %{"0" => "1", "1" => "2", ...}
    # Sort by key and join values, filtering out empty values
    code
    |> Enum.sort_by(fn {k, _v} -> String.to_integer(k) end)
    |> Enum.map(fn {_k, v} -> v end)
    |> Enum.reject(&(&1 == "" || &1 == nil))
    |> Enum.join("")
  end

  defp normalize_verification_code(code) when is_list(code) do
    # Join array elements and filter out empty values
    code
    |> Enum.reject(&(&1 == "" || &1 == nil))
    |> Enum.join("")
  end

  defp normalize_verification_code(code) when is_binary(code) do
    code
  end

  defp normalize_verification_code(_), do: ""
end
