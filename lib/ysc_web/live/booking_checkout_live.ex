defmodule YscWeb.BookingCheckoutLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, BookingLocker}
  alias Ysc.MoneyHelper
  alias Ysc.Repo
  require Logger

  @impl true
  def mount(%{"booking_id" => booking_id}, _session, socket) do
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
            booking = Repo.preload(booking, [:room, room: :room_category])

            # Check if booking is still in hold status
            if booking.status != :hold do
              {:ok,
               socket
               |> put_flash(:error, "This booking is no longer available for payment.")
               |> redirect(to: get_property_redirect_path(booking.property))}
            else
              # Calculate price
              case calculate_booking_price(booking) do
                {:ok, total_price, price_breakdown} ->
                  # Preload user association
                  booking = Repo.preload(booking, [:user])

                  socket =
                    assign(socket,
                      booking: booking,
                      total_price: total_price,
                      price_breakdown: price_breakdown,
                      payment_intent: nil,
                      payment_error: nil,
                      show_payment_form: false,
                      timezone: timezone
                    )

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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-bold text-zinc-900">Complete Your Booking</h1>
        <p class="text-zinc-600 mt-2">Review your booking details and complete payment</p>
      </div>

      <div class="space-y-6">
        <!-- Booking Summary -->
        <div>
          <div class="bg-white rounded-lg border border-zinc-200 p-6">
            <h2 class="text-xl font-semibold text-zinc-900 mb-4">Booking Summary</h2>

            <div class="space-y-4">
              <div>
                <div class="text-sm text-zinc-600">Property</div>
                <div class="font-medium text-zinc-900">
                  <%= String.capitalize(Atom.to_string(@booking.property)) %>
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Check-in</div>
                <div class="font-medium text-zinc-900">
                  <%= format_date(@booking.checkin_date, @timezone) %>
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Check-out</div>
                <div class="font-medium text-zinc-900">
                  <%= format_date(@booking.checkout_date, @timezone) %>
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Nights</div>
                <div class="font-medium text-zinc-900">
                  <%= Date.diff(@booking.checkout_date, @booking.checkin_date) %>
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Guests</div>
                <div class="font-medium text-zinc-900"><%= @booking.guests_count %></div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Booking Mode</div>
                <div class="font-medium text-zinc-900">
                  <%= if @booking.booking_mode == :buyout do %>
                    Full Buyout
                  <% else %>
                    Per Guest
                  <% end %>
                </div>
              </div>

              <div>
                <div class="text-sm text-zinc-600">Reference</div>
                <div class="font-mono text-sm text-zinc-900"><%= @booking.reference_id %></div>
              </div>
            </div>
          </div>
        </div>
        <!-- Payment Section -->
        <div>
          <div class="bg-white rounded-lg border border-zinc-200 p-6">
            <h2 class="text-xl font-semibold text-zinc-900 mb-4">Payment</h2>
            <!-- Price Breakdown -->
            <div class="space-y-3 mb-6">
              <%= if @price_breakdown do %>
                <%= render_price_breakdown(assigns) %>
              <% end %>

              <div class="border-t border-zinc-200 pt-3">
                <div class="flex justify-between items-center">
                  <span class="text-lg font-semibold text-zinc-900">Total</span>
                  <span class="text-2xl font-bold text-zinc-900">
                    <%= MoneyHelper.format_money!(@total_price) %>
                  </span>
                </div>
              </div>
            </div>
            <!-- Payment Error -->
            <div :if={@payment_error} class="mb-4 p-3 bg-red-50 border border-red-200 rounded">
              <p class="text-sm text-red-800"><%= @payment_error %></p>
            </div>
            <!-- Payment Form -->
            <div :if={@show_payment_form && @payment_intent}>
              <div
                id="stripe-payment-container"
                phx-hook="StripeElements"
                data-client-secret={@payment_intent.client_secret}
                data-booking-id={@booking.id}
              >
                <div id="payment-element">
                  <!-- Stripe Elements will mount here -->
                </div>
                <div id="payment-message" class="hidden mt-4"></div>
              </div>

              <button
                id="submit-payment"
                type="button"
                class="w-full mt-4 bg-blue-600 hover:bg-blue-700 text-white font-semibold py-3 px-4 rounded-lg transition duration-200 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                Pay <%= MoneyHelper.format_money!(@total_price) %>
              </button>
            </div>
            <!-- Hold Expiry Warning -->
            <div
              :if={@booking.hold_expires_at}
              class="mt-4 p-3 bg-yellow-50 border border-yellow-200 rounded"
            >
              <p class="text-xs text-yellow-800">
                Your booking will be held until <%= format_datetime(
                  @booking.hold_expires_at,
                  @timezone
                ) %>.
                Please complete payment before then.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_price_breakdown(assigns) do
    ~H"""
    <%= if @booking.booking_mode == :day do %>
      <%= if @price_breakdown[:nights] && @price_breakdown[:guests_count] do %>
        <div class="flex justify-between text-sm">
          <span class="text-zinc-600">
            <%= @price_breakdown.guests_count %> guest(s) × <%= @price_breakdown.nights %> night(s)
          </span>
          <span class="text-zinc-900">
            <%= if @price_breakdown[:price_per_guest_per_night] do %>
              @ <%= MoneyHelper.format_money!(@price_breakdown.price_per_guest_per_night) %>/guest/night
            <% end %>
          </span>
        </div>
      <% end %>
    <% end %>
    <%= if @booking.booking_mode == :buyout do %>
      <%= if @price_breakdown[:nights] do %>
        <div class="flex justify-between text-sm">
          <span class="text-zinc-600">
            <%= @price_breakdown.nights %> night(s)
          </span>
          <span class="text-zinc-900">
            <%= if @price_breakdown[:price_per_night] do %>
              @ <%= MoneyHelper.format_money!(@price_breakdown.price_per_night) %>/night
            <% end %>
          </span>
        </div>
      <% end %>
    <% end %>
    <%= if @booking.booking_mode == :room do %>
      <%= if @price_breakdown[:nights] do %>
        <div class="flex justify-between text-sm">
          <span class="text-zinc-600">
            <%= @price_breakdown.nights %> night(s)
            <%= if @price_breakdown[:guests_count] do %>
              × <%= @price_breakdown.guests_count %> guest(s)
            <% end %>
            <%= if @price_breakdown[:children_count] && @price_breakdown.children_count > 0 do %>
              × <%= @price_breakdown.children_count %> child(ren)
            <% end %>
          </span>
          <span class="text-zinc-900">
            <%= if @price_breakdown[:base_per_night] do %>
              Base: <%= MoneyHelper.format_money!(@price_breakdown.base_per_night) %>/night
            <% end %>
            <%= if @price_breakdown[:children_per_night] && Money.positive?(@price_breakdown.children_per_night) do %>
              + Children: <%= MoneyHelper.format_money!(@price_breakdown.children_per_night) %>/night
            <% end %>
          </span>
        </div>
      <% end %>
    <% end %>
    """
  end

  @impl true
  def handle_event("payment-success", %{"payment_intent_id" => payment_intent_id}, socket) do
    case process_payment_success(socket.assigns.booking, payment_intent_id) do
      {:ok, booking} ->
        {:noreply,
         socket
         |> put_flash(:info, "Payment successful! Your booking is confirmed.")
         |> push_navigate(to: ~p"/bookings/#{booking.id}/receipt")}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           payment_error: "Failed to process payment: #{inspect(reason)}"
         )}
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
          {:ok, total} ->
            {:ok, total, %{nights: nights, price_per_night: Money.div(total, nights) |> elem(1)}}

          error ->
            error
        end

      :room ->
        # For room bookings, we need the room_id
        room_id = booking.room_id || if booking.room, do: booking.room.id, else: nil
        children_count = booking.children_count || 0

        if is_nil(room_id) do
          {:error, :room_id_required}
        else
          case Bookings.calculate_booking_price(
                 booking.property,
                 booking.checkin_date,
                 booking.checkout_date,
                 :room,
                 room_id,
                 booking.guests_count,
                 children_count
               ) do
            {:ok, total, breakdown} when is_map(breakdown) ->
              # Room booking returns breakdown with detailed pricing
              {:ok, total,
               %{
                 nights: nights,
                 guests_count: booking.guests_count,
                 children_count: children_count,
                 base: breakdown.base,
                 children: breakdown.children,
                 base_per_night: breakdown.base_per_night,
                 children_per_night: breakdown.children_per_night
               }}

            {:ok, total} ->
              # Fallback if no breakdown returned
              {:ok, total,
               %{
                 nights: nights,
                 guests_count: booking.guests_count,
                 children_count: children_count
               }}

            error ->
              error
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
          {:ok, total} ->
            price_per_guest_per_night =
              if nights > 0 and booking.guests_count > 0 do
                Money.div(total, nights * booking.guests_count) |> elem(1)
              else
                Money.new(0, :USD)
              end

            {:ok, total,
             %{
               nights: nights,
               guests_count: booking.guests_count,
               price_per_guest_per_night: price_per_guest_per_night
             }}

          error ->
            error
        end

      _ ->
        {:error, :invalid_booking_mode}
    end
  end

  defp create_payment_intent(booking, total_amount, user) do
    amount_cents = money_to_cents(total_amount)

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

    case Stripe.PaymentIntent.create(payment_intent_params) do
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
    case Stripe.PaymentIntent.retrieve(payment_intent_id, %{
           expand: ["payment_method", "charges"]
         }) do
      {:ok, payment_intent} ->
        if payment_intent.status == "succeeded" do
          # Process payment in ledger
          case process_ledger_payment(booking, payment_intent) do
            {:ok, payment} ->
              # Confirm booking
              case BookingLocker.confirm_booking(booking.id) do
                {:ok, confirmed_booking} ->
                  {:ok, confirmed_booking}

                {:error, reason} ->
                  Logger.error("Failed to confirm booking: #{inspect(reason)}")
                  {:error, :booking_confirmation_failed}
              end

            {:error, reason} ->
              Logger.error("Failed to process ledger payment: #{inspect(reason)}")
              {:error, :payment_processing_failed}
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
    stripe_fee = calculate_stripe_fee(amount)

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

  defp calculate_stripe_fee(amount) do
    # Stripe fee is 2.9% + $0.30
    fee_percentage = Decimal.new("0.029")
    flat_fee = Money.new(30, :USD)

    case Money.mult(amount, fee_percentage) do
      {:ok, percentage_fee} ->
        case Money.add(percentage_fee, flat_fee) do
          {:ok, total_fee} -> total_fee
          {:error, _} -> flat_fee
        end

      {:error, _} ->
        flat_fee
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

  defp cents_to_money(cents, currency \\ :USD) when is_integer(cents) do
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
        case Stripe.PaymentMethod.retrieve(pm_id) do
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
  defp format_date(%Date{} = date, timezone) do
    # Dates don't have timezone, but we format them consistently
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp format_date(nil, _timezone), do: "—"
  defp format_date(_, _timezone), do: "—"

  defp format_datetime(%DateTime{} = datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%B %d, %Y at %I:%M %p %Z")
  end

  defp format_datetime(nil, _timezone), do: "—"
  defp format_datetime(_, _timezone), do: "—"

  defp get_property_redirect_path(property) do
    case property do
      :tahoe -> ~p"/bookings/tahoe"
      :clear_lake -> ~p"/bookings/clear-lake"
      _ -> ~p"/"
    end
  end
end
