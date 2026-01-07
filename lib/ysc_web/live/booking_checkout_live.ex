defmodule YscWeb.BookingCheckoutLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, BookingLocker}
  alias Ysc.MoneyHelper
  alias Ysc.Repo
  require Logger

  @impl true
  def mount(%{"booking_id" => booking_id}, _session, socket) do
    # Schedule periodic expiration check
    if connected?(socket) do
      Process.send_after(self(), :check_booking_expiration, 5_000)
    end

    user = socket.assigns.current_user

    # Get user timezone from connect params
    connect_params = get_connect_params(socket) || %{}
    timezone = Map.get(connect_params, "timezone", "America/Los_Angeles")

    if is_nil(user) do
      {:ok,
       socket
       |> put_flash(:error, "You must be signed in to complete your booking.")
       |> redirect(to: ~p"/")}
    else
      case Repo.get(Booking, booking_id) do
        nil ->
          {:ok,
           socket
           |> put_flash(:error, "Booking not found.")
           |> redirect(to: ~p"/")}

        booking ->
          # Verify booking belongs to user
          if booking.user_id != user.id do
            {:ok,
             socket
             |> put_flash(:error, "You don't have permission to view this booking.")
             |> redirect(to: get_property_redirect_path(booking.property))}
          else
            # Preload room before calculating price (needed for room bookings)
            booking = Repo.preload(booking, [:rooms, rooms: :room_category])

            # Check if booking is still in hold status
            if booking.status != :hold do
              {:ok,
               socket
               |> put_flash(:error, "This booking is no longer available for payment.")
               |> redirect(to: get_property_redirect_path(booking.property))}
            else
              # Check if booking has expired
              is_expired = booking_expired?(booking)

              if is_expired do
                {:ok,
                 socket
                 |> put_flash(
                   :error,
                   "This booking has expired and is no longer available for payment."
                 )
                 |> redirect(to: get_property_redirect_path(booking.property))}
              else
                # Calculate price
                case calculate_booking_price(booking) do
                  {:ok, total_price, price_breakdown} ->
                    # Preload user association
                    booking = Repo.preload(booking, [:user])

                    # Re-check expiration after price calculation
                    is_expired = booking_expired?(booking)

                    socket =
                      assign(socket,
                        booking: booking,
                        total_price: total_price,
                        price_breakdown: price_breakdown,
                        payment_intent: nil,
                        payment_error: nil,
                        show_payment_form: false,
                        is_expired: is_expired,
                        timezone: timezone
                      )

                    if is_expired do
                      {:ok,
                       assign(socket,
                         payment_error:
                           "This booking has expired and is no longer available for payment."
                       )}
                    else
                      # Create Stripe payment intent
                      case create_payment_intent(booking, total_price, user) do
                        {:ok, payment_intent} ->
                          {:ok,
                           assign(socket,
                             payment_intent: payment_intent,
                             show_payment_form: true
                           )}

                        {:error, reason} ->
                          {:ok,
                           assign(socket,
                             payment_error: "Failed to initialize payment: #{reason}"
                           )}
                      end
                    end

                  {:error, reason} ->
                    {:ok,
                     socket
                     |> put_flash(:error, "Failed to calculate price: #{inspect(reason)}")
                     |> redirect(to: get_property_redirect_path(booking.property))}
                end
              end
            end
          end
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10 max-w-screen-xl mx-auto px-4">
      <div class="prose prose-zinc mb-8">
        <h1>Complete Your Booking</h1>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8 items-start">
        <!-- Left Column: Booking Summary and Payment -->
        <div class="lg:col-span-2 space-y-6">
          <!-- Visual Booking Summary -->
          <div class="flex items-center gap-6 p-6 bg-zinc-50 rounded-lg border border-zinc-200">
            <div class="h-20 w-20 bg-zinc-200 rounded-lg overflow-hidden flex-shrink-0">
              <img
                src={get_property_thumbnail(@booking.property)}
                alt={atom_to_readable(@booking.property) <> " Cabin"}
                class="object-cover h-full w-full"
              />
            </div>
            <div class="flex-1">
              <h2 class="text-2xl font-bold text-zinc-900">
                <%= atom_to_readable(@booking.property) %> Cabin
              </h2>
              <p class="text-zinc-500 mt-1">
                <%= format_date_short(@booking.checkin_date, @timezone) %> — <%= format_date_short(
                  @booking.checkout_date,
                  @timezone
                ) %>, <%= Calendar.strftime(@booking.checkout_date, "%Y") %> (<%= Date.diff(
                  @booking.checkout_date,
                  @booking.checkin_date
                ) %> <%= if Date.diff(
                              @booking.checkout_date,
                              @booking.checkin_date
                            ) == 1,
                            do: "night",
                            else: "nights" %>)
              </p>
              <div class="mt-2 flex flex-wrap items-center gap-3 text-sm">
                <span class="text-zinc-600">
                  <%= @booking.guests_count %> <%= if @booking.guests_count == 1,
                    do: "adult",
                    else: "adults" %>
                  <%= if @booking.children_count && @booking.children_count > 0 do %>
                    , <%= @booking.children_count %> <%= if @booking.children_count == 1,
                      do: "child",
                      else: "children" %>
                  <% end %>
                </span>
                <%= if @booking.booking_mode == :room && Ecto.assoc_loaded?(@booking.rooms) &&
                      length(@booking.rooms) > 0 do %>
                  <span class="text-zinc-400">•</span>
                  <span class="text-zinc-600">
                    <%= Enum.map(@booking.rooms, & &1.name) |> Enum.join(", ") %>
                  </span>
                <% end %>
              </div>
            </div>
          </div>
          <!-- Payment Section -->
          <div class="bg-white rounded-lg border border-zinc-200 p-8 shadow-sm">
            <h2 class="text-xl font-bold mb-6">Secure Payment</h2>
            <!-- Payment Error -->
            <div :if={@payment_error} class="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg">
              <p class="text-sm text-red-800"><%= @payment_error %></p>
            </div>
            <!-- Payment Form -->
            <div :if={@show_payment_form && @payment_intent && !@is_expired}>
              <div
                id="stripe-payment-container"
                phx-hook="StripeElements"
                data-client-secret={@payment_intent.client_secret}
                data-booking-id={@booking.id}
              >
                <div id="payment-element" class="mb-6">
                  <!-- Stripe Elements will mount here -->
                </div>
                <div id="payment-message" class="hidden mt-4"></div>
              </div>

              <div class="flex flex-col sm:flex-row gap-4 pt-6 border-t border-zinc-100">
                <.button
                  id="submit-payment"
                  type="button"
                  class="flex-1 w-full text-lg py-3.5"
                  disabled={@is_expired}
                >
                  <.icon name="hero-lock-closed" class="w-5 h-5 -mt-1 me-1" />
                  <span class="text-lg font-semibold">
                    Pay <%= MoneyHelper.format_money!(@total_price) %> Securely
                  </span>
                </.button>
                <.button_link
                  type="button"
                  phx-click="cancel-booking"
                  phx-confirm="Are you sure you want to cancel this booking? The availability will be released immediately."
                  color="red"
                  class="text-zinc-500 hover:text-white"
                >
                  Cancel
                </.button_link>
              </div>

              <div class="mt-6 flex items-center justify-center gap-2 text-zinc-400">
                <.icon name="hero-lock-closed" class="w-4 h-4" />
                <span class="text-xs uppercase tracking-widest font-semibold">
                  Encrypted & Secure
                </span>
              </div>
            </div>
            <!-- Expired Booking Message -->
            <div
              :if={assigns[:is_expired] && @is_expired}
              class="p-6 bg-red-50 border border-red-200 rounded-lg"
            >
              <p class="text-sm font-semibold text-red-800 mb-2">Booking Expired</p>
              <p class="text-sm text-red-700 mb-4">
                This booking has expired and is no longer available for payment. Please create a new booking.
              </p>
              <a
                href={get_property_redirect_path(@booking.property)}
                class="inline-block text-sm font-medium text-red-800 hover:text-red-900 underline"
              >
                Create New Booking →
              </a>
            </div>
          </div>
        </div>
        <!-- Right Column: Countdown Timer and Price Details -->
        <aside class="space-y-6 lg:sticky lg:top-24">
          <!-- Hold Expiry Countdown -->
          <div
            :if={@booking.hold_expires_at && (!assigns[:is_expired] || !@is_expired)}
            class="bg-amber-50 border border-amber-200 rounded-lg p-6"
          >
            <div class="flex items-center gap-3 text-amber-800 mb-2">
              <.icon name="hero-clock" class="w-5 h-5 animate-pulse" />
              <span class="font-bold">Hold Expires</span>
            </div>
            <p class="text-sm text-amber-700 leading-relaxed">
              We've reserved your rooms! Complete payment within
              <span
                class="font-bold tabular-nums"
                id="hold-countdown"
                phx-hook="HoldCountdown"
                data-expires-at={DateTime.to_iso8601(@booking.hold_expires_at)}
                data-timezone={@timezone}
              >
                <%= calculate_remaining_time(@booking.hold_expires_at) %>
              </span>
              before they are released.
            </p>
          </div>
          <!-- Price Details -->
          <div class="bg-zinc-900 text-white rounded-lg p-6 shadow-xl">
            <h3 class="text-sm font-bold text-zinc-400 uppercase tracking-widest mb-4">
              Price Details
            </h3>
            <div class="space-y-3">
              <%= if @price_breakdown do %>
                <%= render_price_breakdown_sidebar(assigns) %>
              <% end %>
              <div class="pt-4 border-t border-zinc-700 flex justify-between items-baseline">
                <span class="text-lg font-bold">Total</span>
                <span class="text-3xl font-black text-blue-400">
                  <%= MoneyHelper.format_money!(@total_price) %>
                </span>
              </div>
            </div>
          </div>
          <!-- What Happens Next -->
          <div class="bg-white rounded-lg border border-zinc-200 p-6">
            <h3 class="text-lg font-bold text-zinc-900 mb-4">What Happens Next?</h3>
            <ol class="space-y-3 text-sm text-zinc-600">
              <li class="flex items-start gap-3">
                <span class="flex-shrink-0 w-6 h-6 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center font-bold text-xs">
                  1
                </span>
                <span>Complete your secure payment above</span>
              </li>
              <li class="flex items-start gap-3">
                <span class="flex-shrink-0 w-6 h-6 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center font-bold text-xs">
                  2
                </span>
                <span>Receive instant confirmation email with booking details</span>
              </li>
              <li class="flex items-start gap-3">
                <span class="flex-shrink-0 w-6 h-6 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center font-bold text-xs">
                  3
                </span>
                <span>
                  Get cabin access information (door code or key instructions) via email before check-in
                </span>
              </li>
              <li class="flex items-start gap-3">
                <span class="flex-shrink-0 w-6 h-6 bg-blue-100 text-blue-600 rounded-full flex items-center justify-center font-bold text-xs">
                  4
                </span>
                <span>Access your booking details and manage your reservation anytime</span>
              </li>
            </ol>
          </div>
          <!-- Booking Reference (Help Section) -->
          <div class="bg-zinc-50 rounded-lg border border-zinc-200 p-6">
            <h3 class="text-sm font-semibold text-zinc-900 mb-2">Booking Reference</h3>
            <div class="inline-flex items-center px-3 py-1.5 bg-white border border-zinc-300 rounded-lg font-mono text-sm font-semibold text-zinc-900">
              <%= @booking.reference_id %>
            </div>
            <p class="mt-2 text-xs text-zinc-500">
              Save this reference number for your records. You'll also receive it via email.
            </p>
          </div>
        </aside>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("cancel-booking", _params, socket) do
    case BookingLocker.release_hold(socket.assigns.booking.id) do
      {:ok, _canceled_booking} ->
        property = socket.assigns.booking.property
        redirect_path = get_property_redirect_path(property)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Your booking has been canceled and the availability has been released."
         )
         |> redirect(to: redirect_path)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Failed to cancel booking: #{inspect(reason)}. Please try again or contact support."
         )}
    end
  end

  @impl true
  def handle_event("payment-redirect-started", _params, socket) do
    # Acknowledge that the payment redirect has started (no action needed)
    {:noreply, socket}
  end

  @impl true
  def handle_event("payment-success", %{"payment_intent_id" => payment_intent_id}, socket) do
    # Check if booking has expired before processing payment
    if booking_expired?(socket.assigns.booking) do
      {:noreply,
       socket
       |> assign(
         payment_error: "This booking has expired and is no longer available for payment.",
         show_payment_form: false
       )
       |> put_flash(:error, "This booking has expired. Please create a new booking.")}
    else
      case process_payment_success(socket.assigns.booking, payment_intent_id) do
        {:ok, booking} ->
          {:noreply,
           socket
           |> put_flash(:info, "Payment successful! Your booking is confirmed.")
           |> push_navigate(to: ~p"/bookings/#{booking.id}/receipt?confetti=true")}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             payment_error: "Failed to process payment: #{inspect(reason)}"
           )}
      end
    end
  end

  @impl true
  def handle_info(:check_booking_expiration, socket) do
    # Check if booking has expired
    if booking_expired?(socket.assigns.booking) do
      # Reload booking to get latest status
      booking = Repo.get!(Booking, socket.assigns.booking.id) |> Repo.preload([:user, :rooms])

      {:noreply,
       socket
       |> assign(
         booking: booking,
         is_expired: true,
         show_payment_form: false,
         payment_error: "This booking has expired and is no longer available for payment."
       )
       |> put_flash(:error, "This booking has expired. Please create a new booking.")}
    else
      # Schedule next check in 5 seconds
      Process.send_after(self(), :check_booking_expiration, 5_000)
      {:noreply, socket}
    end
  end

  ## Private Functions

  defp calculate_booking_price(booking) do
    nights = Date.diff(booking.checkout_date, booking.checkin_date)

    case booking.booking_mode do
      :buyout ->
        case Bookings.calculate_booking_price(
               booking.property,
               booking.checkin_date,
               booking.checkout_date,
               :buyout,
               nil,
               booking.guests_count,
               0
             ) do
          {:ok, total, breakdown} ->
            # Use breakdown if available, otherwise create a simple one
            final_breakdown =
              if breakdown && is_map(breakdown) do
                Map.merge(breakdown, %{nights: nights})
              else
                %{nights: nights, price_per_night: Money.div(total, nights) |> elem(1)}
              end

            {:ok, total, final_breakdown}

          error ->
            error
        end

      :room ->
        # For room bookings, always recalculate to ensure correct pricing
        # (stored pricing may be incorrect if calculated per-room instead of per-guest)
        children_count = booking.children_count || 0

        room_ids =
          if Ecto.assoc_loaded?(booking.rooms) && length(booking.rooms) > 0 do
            Enum.map(booking.rooms, & &1.id)
          else
            []
          end

        if room_ids == [] do
          {:error, :rooms_required}
        else
          # Always recalculate price correctly for per-guest pricing
          # For per-guest pricing, calculate once for total guests regardless of room count
          case calculate_multi_room_price_for_checkout(
                 booking.property,
                 booking.checkin_date,
                 booking.checkout_date,
                 room_ids,
                 booking.guests_count,
                 children_count,
                 nights
               ) do
            {:ok, recalculated_total, breakdown} ->
              {:ok, recalculated_total, breakdown}

            error ->
              # Fallback to stored pricing if recalculation fails
              if booking.total_price && booking.pricing_items do
                {:ok, booking.total_price,
                 extract_price_breakdown_from_pricing_items(booking.pricing_items, nights)}
              else
                error
              end
          end
        end

      :day ->
        case Bookings.calculate_booking_price(
               booking.property,
               booking.checkin_date,
               booking.checkout_date,
               :day,
               nil,
               booking.guests_count,
               0
             ) do
          {:ok, total, breakdown} ->
            # Use breakdown if available, otherwise create a simple one
            final_breakdown =
              if breakdown && is_map(breakdown) do
                Map.merge(breakdown, %{nights: nights, guests_count: booking.guests_count})
              else
                price_per_guest_per_night =
                  if nights > 0 and booking.guests_count > 0 do
                    Money.div(total, nights * booking.guests_count) |> elem(1)
                  else
                    Money.new(0, :USD)
                  end

                %{
                  nights: nights,
                  guests_count: booking.guests_count,
                  price_per_guest_per_night: price_per_guest_per_night
                }
              end

            {:ok, total, final_breakdown}

          error ->
            error
        end

      _ ->
        {:error, :invalid_booking_mode}
    end
  end

  defp create_payment_intent(booking, total_amount, user) do
    amount_cents = money_to_cents(total_amount)

    # Note: Stripe PaymentIntents don't support expires_at parameter.
    # The expires_at parameter is only available for Checkout Sessions, not PaymentIntents.
    # Since we're using PaymentIntents with Stripe Elements (embedded form), we handle
    # expiration server-side via HoldExpiryWorker that cancels expired bookings and releases inventory.
    payment_intent_params = %{
      amount: amount_cents,
      currency: "usd",
      metadata: %{
        booking_id: booking.id,
        booking_reference: booking.reference_id,
        property: Atom.to_string(booking.property),
        user_id: user.id
      },
      description:
        "Booking #{booking.reference_id} - #{String.capitalize(Atom.to_string(booking.property))}",
      automatic_payment_methods: %{
        enabled: true
      }
    }

    # Add customer if user has Stripe ID
    payment_intent_params =
      if user.stripe_id do
        Map.put(payment_intent_params, :customer, user.stripe_id)
      else
        payment_intent_params
      end

    # Use booking reference ID as idempotency key to prevent duplicate charges
    # If the same reference is used again, Stripe will return the existing payment intent
    idempotency_key = "booking_#{booking.reference_id}"

    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.create_payment_intent(payment_intent_params,
           headers: %{"Idempotency-Key" => idempotency_key}
         ) do
      {:ok, payment_intent} ->
        {:ok, payment_intent}

      {:error, %Stripe.Error{} = error} ->
        Logger.error("Stripe payment intent creation failed: #{inspect(error)}")
        {:error, error.message}

      {:error, reason} ->
        Logger.error("Payment intent creation failed: #{inspect(reason)}")
        {:error, "Payment initialization failed"}
    end
  end

  defp process_payment_success(booking, payment_intent_id_or_secret) do
    # Extract payment intent ID if a client secret was passed
    payment_intent_id =
      if String.contains?(payment_intent_id_or_secret, "_secret_") do
        payment_intent_id_or_secret
        |> String.split("_secret_")
        |> List.first()
      else
        payment_intent_id_or_secret
      end

    # Retrieve payment intent to verify (expand payment_method and charges)
    stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

    case stripe_client.retrieve_payment_intent(payment_intent_id, %{
           expand: ["payment_method", "charges"]
         }) do
      {:ok, payment_intent} ->
        if payment_intent.status == "succeeded" do
          # Reload booking to get latest status (webhook may have already confirmed it)
          reloaded_booking = Repo.get!(Booking, booking.id) |> Repo.preload([:rooms, :user])

          # Check if booking is already confirmed (e.g., by webhook)
          if reloaded_booking.status == :complete do
            Logger.info(
              "Booking already confirmed (likely by webhook), returning existing booking",
              booking_id: booking.id,
              payment_intent_id: payment_intent_id
            )

            {:ok, reloaded_booking}
          else
            # Process payment in ledger (handles idempotency - returns existing payment if already processed)
            case process_ledger_payment(reloaded_booking, payment_intent) do
              {:ok, _payment} ->
                # Confirm booking (only if not already confirmed)
                case BookingLocker.confirm_booking(reloaded_booking.id) do
                  {:ok, confirmed_booking} ->
                    {:ok, confirmed_booking}

                  {:error, :invalid_status} ->
                    # Booking was confirmed between reload and confirm attempt (race condition)
                    # Reload again and return the confirmed booking
                    final_booking =
                      Repo.get!(Booking, reloaded_booking.id) |> Repo.preload([:rooms, :user])

                    if final_booking.status == :complete do
                      Logger.info(
                        "Booking confirmed by another process, returning confirmed booking",
                        booking_id: booking.id
                      )

                      {:ok, final_booking}
                    else
                      Logger.error("Failed to confirm booking: invalid status",
                        booking_id: booking.id,
                        status: final_booking.status
                      )

                      {:error, :booking_confirmation_failed}
                    end

                  {:error, reason} ->
                    Logger.error("Failed to confirm booking: #{inspect(reason)}")
                    {:error, :booking_confirmation_failed}
                end

              {:error, reason} ->
                Logger.error("Failed to process ledger payment: #{inspect(reason)}")
                {:error, :payment_processing_failed}
            end
          end
        else
          {:error, :payment_not_succeeded}
        end

      {:error, reason} ->
        Logger.error("Failed to retrieve payment intent: #{inspect(reason)}")
        {:error, :payment_verification_failed}
    end
  end

  defp process_ledger_payment(booking, payment_intent) do
    amount = cents_to_money(payment_intent.amount, :USD)
    # Use consolidated fee extraction from Stripe.WebhookHandler
    stripe_fee = Ysc.Stripe.WebhookHandler.extract_stripe_fee_from_payment_intent(payment_intent)

    # Extract and sync payment method to get our internal ULID
    payment_method_id = extract_and_sync_payment_method(payment_intent, booking.user_id)

    attrs = %{
      user_id: booking.user_id,
      amount: amount,
      entity_type: :booking,
      entity_id: booking.id,
      external_payment_id: payment_intent.id,
      stripe_fee: stripe_fee,
      description: "Booking payment - #{booking.reference_id}",
      property: booking.property,
      payment_method_id: payment_method_id
    }

    case Ysc.Ledgers.process_payment(attrs) do
      {:ok, {payment, _transaction, _entries}} ->
        {:ok, payment}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper to extract price breakdown from stored pricing_items (fallback only)
  # For per-guest pricing with multiple rooms, aggregate into single line item
  defp extract_price_breakdown_from_pricing_items(pricing_items, nights)
       when is_map(pricing_items) do
    case pricing_items do
      %{"type" => "room", "rooms" => rooms} when is_list(rooms) and length(rooms) > 0 ->
        # Multiple rooms - for per-guest pricing, show single aggregated line item
        guests_count = pricing_items["guests_count"] || 0
        children_count = pricing_items["children_count"] || 0

        %{
          nights: nights,
          guests_count: guests_count,
          children_count: children_count,
          multi_room: true,
          room_count: length(rooms)
        }

      %{"type" => "room"} ->
        # Single room (legacy format)
        %{
          nights: nights,
          guests_count: pricing_items["guests_count"] || 0,
          children_count: pricing_items["children_count"] || 0
        }

      _ ->
        %{nights: nights}
    end
  end

  defp extract_price_breakdown_from_pricing_items(_, nights), do: %{nights: nights}

  # Helper to calculate price for multiple rooms (fallback)
  # For per-guest pricing, calculate once for total guests regardless of room count
  defp calculate_multi_room_price_for_checkout(
         property,
         checkin_date,
         checkout_date,
         room_ids,
         guests_count,
         children_count,
         nights
       ) do
    # For per-guest pricing, calculate price once using the first room
    # The number of rooms doesn't affect the price - only total guests matter
    first_room_id = List.first(room_ids)

    case Bookings.calculate_booking_price(
           property,
           checkin_date,
           checkout_date,
           :room,
           first_room_id,
           guests_count,
           children_count
         ) do
      {:ok, total, breakdown} when is_map(breakdown) ->
        # Extract all pricing details from breakdown for detailed display
        base_total = breakdown[:base]
        children_total = breakdown[:children]
        billable_people = breakdown[:billable_people] || guests_count
        adult_price_per_night = breakdown[:adult_price_per_night]
        children_price_per_night = breakdown[:children_price_per_night]

        # Calculate per-night rates if not already provided
        base_per_night =
          if base_total && nights > 0 do
            case Money.div(base_total, nights) do
              {:ok, per_night} -> per_night
              _ -> adult_price_per_night
            end
          else
            adult_price_per_night
          end

        children_per_night =
          if children_total && nights > 0 && children_count > 0 do
            # Calculate per-child-per-night price
            case Money.div(children_total, children_count * nights) do
              {:ok, per_night} -> per_night
              _ -> children_price_per_night
            end
          else
            children_price_per_night
          end

        # Return complete breakdown for detailed display
        breakdown_map = %{
          nights: nights,
          guests_count: guests_count,
          children_count: children_count,
          billable_people: billable_people,
          multi_room: true,
          room_count: length(room_ids)
        }

        breakdown_map =
          if base_total do
            Map.put(breakdown_map, :base, base_total)
          else
            breakdown_map
          end

        breakdown_map =
          if children_total do
            Map.put(breakdown_map, :children, children_total)
          else
            breakdown_map
          end

        breakdown_map =
          if base_per_night do
            Map.put(breakdown_map, :base_per_night, base_per_night)
          else
            breakdown_map
          end

        breakdown_map =
          if adult_price_per_night do
            Map.put(breakdown_map, :adult_price_per_night, adult_price_per_night)
          else
            breakdown_map
          end

        breakdown_map =
          if children_per_night && Money.positive?(children_per_night) do
            Map.put(breakdown_map, :children_per_night, children_per_night)
          else
            breakdown_map
          end

        {:ok, total, breakdown_map}

      {:ok, total, breakdown} ->
        # Use breakdown if available, otherwise create a simple one
        final_breakdown =
          if breakdown && is_map(breakdown) do
            Map.merge(breakdown, %{
              nights: nights,
              guests_count: guests_count,
              children_count: children_count,
              multi_room: true,
              room_count: length(room_ids)
            })
          else
            %{
              nights: nights,
              guests_count: guests_count,
              children_count: children_count,
              multi_room: true,
              room_count: length(room_ids)
            }
          end

        {:ok, total, final_breakdown}

      error ->
        error
    end
  end

  # Helper functions for money conversion
  defp money_to_cents(%Money{amount: amount, currency: :USD}) do
    # Use Decimal for precise conversion to avoid floating-point errors
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(%Money{amount: amount, currency: _currency}) do
    # For other currencies, use same conversion
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(_), do: 0

  defp cents_to_money(cents, currency)

  defp cents_to_money(cents, currency) when is_integer(cents) do
    cents_decimal = Decimal.new(cents)
    dollars = Decimal.div(cents_decimal, Decimal.new(100))
    Money.new(currency, dollars)
  end

  defp cents_to_money(_, _), do: Money.new(0, :USD)

  # Extract and sync payment method from Stripe
  defp extract_and_sync_payment_method(payment_intent, user_id) do
    # Try to get payment method from payment intent
    stripe_payment_method_id =
      cond do
        # Payment intent might have payment_method as a string ID
        is_binary(payment_intent.payment_method) ->
          payment_intent.payment_method

        # Or it might be expanded as an object
        is_map(payment_intent.payment_method) ->
          payment_intent.payment_method.id

        # Or get it from the first charge (charges is a List struct with data field)
        payment_intent.charges && payment_intent.charges.data &&
            length(payment_intent.charges.data) > 0 ->
          first_charge = List.first(payment_intent.charges.data)
          # Payment method might be a string ID or an expanded object
          cond do
            is_binary(first_charge.payment_method) ->
              first_charge.payment_method

            is_map(first_charge.payment_method) && Map.has_key?(first_charge.payment_method, :id) ->
              first_charge.payment_method.id

            true ->
              nil
          end

        true ->
          nil
      end

    case stripe_payment_method_id do
      nil ->
        Logger.info("No payment method found in payment intent",
          payment_intent_id: payment_intent.id
        )

        nil

      pm_id when is_binary(pm_id) ->
        # Retrieve the full payment method from Stripe
        stripe_client = Application.get_env(:ysc, :stripe_client, Ysc.StripeClient)

        case stripe_client.retrieve_payment_method(pm_id) do
          {:ok, stripe_payment_method} ->
            # Get the user to sync the payment method
            user = Ysc.Accounts.get_user!(user_id)

            # Sync the payment method to our database
            case Ysc.Payments.sync_payment_method_from_stripe(user, stripe_payment_method) do
              {:ok, payment_method} ->
                Logger.info("Successfully synced payment method for booking payment",
                  payment_method_id: payment_method.id,
                  stripe_payment_method_id: pm_id,
                  user_id: user_id
                )

                payment_method.id

              {:error, reason} ->
                Logger.warning("Failed to sync payment method for booking payment",
                  stripe_payment_method_id: pm_id,
                  user_id: user_id,
                  error: inspect(reason)
                )

                nil
            end

          {:error, error} ->
            Logger.warning("Failed to retrieve payment method from Stripe",
              payment_method_id: pm_id,
              payment_intent_id: payment_intent.id,
              error: error.message
            )

            nil
        end
    end
  end

  # Timezone-aware formatting functions
  defp format_date_short(%Date{} = date, _timezone) do
    # Shorter format for visual summaries: "Dec 23"
    Calendar.strftime(date, "%b %d")
  end

  defp format_date_short(nil, _timezone), do: "—"
  defp format_date_short(_, _timezone), do: "—"

  defp get_property_redirect_path(property) do
    case property do
      :tahoe -> ~p"/bookings/tahoe"
      :clear_lake -> ~p"/bookings/clear-lake"
      _ -> ~p"/"
    end
  end

  defp get_property_thumbnail(property) do
    case property do
      :tahoe -> ~p"/images/tahoe/tahoe_cabin_main.webp"
      :clear_lake -> ~p"/images/clear_lake/clear_lake_dock.webp"
      _ -> ~p"/images/ysc_logo.png"
    end
  end

  defp render_price_breakdown_sidebar(assigns) do
    ~H"""
    <%= if @booking.booking_mode == :room do %>
      <%= if @price_breakdown[:nights] do %>
        <% nights = @price_breakdown.nights %>
        <% guests_count = @price_breakdown[:guests_count] || 0 %>
        <% children_count = @price_breakdown[:children_count] || 0 %>
        <% billable_people = @price_breakdown[:billable_people] || guests_count %>
        <% adult_price_per_night =
          @price_breakdown[:adult_price_per_night] || @price_breakdown[:base_per_night] %>
        <% children_price_per_night = @price_breakdown[:children_price_per_night] %>
        <% base_total = @price_breakdown[:base] %>
        <% children_total = @price_breakdown[:children] %>
        <!-- Calculate adult_price_per_night from base_total if not available -->
        <% adult_price_per_night =
          if !adult_price_per_night && base_total && nights > 0 && billable_people > 0 do
            case Money.div(base_total, nights * billable_people) do
              {:ok, price} -> price
              _ -> nil
            end
          else
            adult_price_per_night
          end %>
        <!-- Adults pricing -->
        <%= if billable_people > 0 && (base_total || adult_price_per_night) do %>
          <% final_base_total =
            if base_total,
              do: base_total,
              else:
                (if adult_price_per_night && billable_people > 0 && nights > 0 do
                   case Money.mult(adult_price_per_night, billable_people * nights) do
                     {:ok, total} -> total
                     _ -> nil
                   end
                 else
                   nil
                 end) %>
          <div class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
            <div class="text-zinc-400">
              <%= billable_people %> <%= if billable_people == 1, do: "adult", else: "adults" %>
            </div>
            <div class="text-right text-zinc-500 text-xs tabular-nums">
              <%= if adult_price_per_night do %>
                <%= MoneyHelper.format_money!(adult_price_per_night) %>/night
              <% end %>
            </div>
            <div class="text-zinc-400 text-xs">
              × <%= nights %> <%= if nights == 1, do: "night", else: "nights" %>
            </div>
            <div class="text-right font-medium tabular-nums">
              <%= if final_base_total do %>
                <%= MoneyHelper.format_money!(final_base_total) %>
              <% end %>
            </div>
          </div>
        <% end %>
        <!-- Children pricing -->
        <%= if children_count > 0 && (children_total || children_price_per_night) do %>
          <% # Calculate children_price_per_night from children_total if not available
          calculated_children_price_per_night =
            if !children_price_per_night && children_total && children_count > 0 && nights > 0 do
              case Money.div(children_total, children_count * nights) do
                {:ok, price} -> price
                _ -> nil
              end
            else
              children_price_per_night
            end

          final_children_total =
            if children_total,
              do: children_total,
              else:
                (if calculated_children_price_per_night && children_count > 0 && nights > 0 do
                   case Money.mult(calculated_children_price_per_night, children_count * nights) do
                     {:ok, total} -> total
                     _ -> nil
                   end
                 else
                   nil
                 end) %>
          <div class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm mt-3">
            <div class="text-zinc-400">
              <%= children_count %> <%= if children_count == 1, do: "child", else: "children" %>
            </div>
            <div class="text-right text-zinc-500 text-xs tabular-nums">
              <%= if calculated_children_price_per_night do %>
                <%= MoneyHelper.format_money!(calculated_children_price_per_night) %>/night
              <% end %>
            </div>
            <div class="text-zinc-400 text-xs">
              × <%= nights %> <%= if nights == 1, do: "night", else: "nights" %>
            </div>
            <div class="text-right font-medium tabular-nums">
              <%= if final_children_total do %>
                <%= MoneyHelper.format_money!(final_children_total) %>
              <% end %>
            </div>
          </div>
        <% end %>
      <% end %>
    <% else %>
      <!-- Day booking (per guest per night) -->
      <%= if @booking.booking_mode == :day && @price_breakdown[:nights] do %>
        <% nights = @price_breakdown.nights %>
        <% guests_count = @price_breakdown[:guests_count] || 0 %>
        <% price_per_guest_per_night = @price_breakdown[:price_per_guest_per_night] %>
        <%= if guests_count > 0 && price_per_guest_per_night do %>
          <div class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
            <div class="text-zinc-400">
              <%= guests_count %> <%= if guests_count == 1, do: "guest", else: "guests" %>
            </div>
            <div class="text-right text-zinc-500 text-xs tabular-nums">
              <%= MoneyHelper.format_money!(price_per_guest_per_night) %>/night
            </div>
            <div class="text-zinc-400 text-xs">
              × <%= nights %> <%= if nights == 1, do: "night", else: "nights" %>
            </div>
            <div class="text-right font-medium tabular-nums">
              <%= case Money.mult(price_per_guest_per_night, guests_count * nights) do
                {:ok, total} -> MoneyHelper.format_money!(total)
                _ -> MoneyHelper.format_money!(@total_price)
              end %>
            </div>
          </div>
        <% else %>
          <!-- Fallback if price_per_guest_per_night not available -->
          <div class="flex justify-between text-sm">
            <span class="text-zinc-400">
              <%= nights %> <%= if nights == 1, do: "night", else: "nights" %>
            </span>
            <span class="font-medium">
              <%= MoneyHelper.format_money!(@total_price) %>
            </span>
          </div>
        <% end %>
      <% else %>
        <!-- Buyout booking -->
        <%= if @price_breakdown[:nights] do %>
          <div class="flex justify-between text-sm">
            <span class="text-zinc-400">
              <%= @price_breakdown.nights %> <%= if @price_breakdown.nights == 1,
                do: "night",
                else: "nights" %>
            </span>
            <span class="font-medium">
              <%= MoneyHelper.format_money!(@total_price) %>
            </span>
          </div>
        <% end %>
      <% end %>
    <% end %>
    """
  end

  defp calculate_remaining_time(%DateTime{} = expires_at) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(expires_at, now, :second)

    if diff_seconds > 0 do
      hours = div(diff_seconds, 3600)
      minutes = div(rem(diff_seconds, 3600), 60)
      seconds = rem(diff_seconds, 60)

      if hours > 0 do
        "#{String.pad_leading(Integer.to_string(hours), 2, "0")}:#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
      else
        "#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(seconds), 2, "0")}"
      end
    else
      "00:00"
    end
  end

  defp calculate_remaining_time(_), do: "—"

  defp booking_expired?(booking) do
    case booking do
      %{status: :hold, hold_expires_at: hold_expires_at} when not is_nil(hold_expires_at) ->
        DateTime.compare(DateTime.utc_now(), hold_expires_at) == :gt

      %{status: :hold} ->
        # No hold_expires_at set, consider it not expired (shouldn't happen, but be safe)
        false

      _ ->
        # Not in hold status, consider it expired for payment purposes
        true
    end
  end

  defp atom_to_readable(atom) when is_binary(atom) do
    atom
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp atom_to_readable(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp atom_to_readable(nil), do: "—"
  defp atom_to_readable(_), do: "—"
end
