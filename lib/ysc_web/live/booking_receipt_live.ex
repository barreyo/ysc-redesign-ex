defmodule YscWeb.BookingReceiptLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, BookingLocker}
  alias Ysc.MoneyHelper
  alias Ysc.Repo
  require Logger
  import Ecto.Query

  @impl true
  def mount(%{"booking_id" => booking_id} = params, _session, socket) do
    user = socket.assigns.current_user

    if is_nil(user) do
      {:ok,
       socket
       |> put_flash(:error, "You must be signed in to view this receipt.")
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
             |> redirect(to: ~p"/")}
          else
            # Preload associations
            booking = Repo.preload(booking, [:user, rooms: :room_category])

            # Handle Stripe redirect parameters
            socket = handle_stripe_redirect(params, booking, socket)

            # Reload booking in case status changed
            booking =
              Repo.get!(Booking, booking_id) |> Repo.preload([:user, rooms: :room_category])

            # Get payment information
            payment = get_booking_payment(booking)

            # Get timezone from connect params
            connect_params =
              case get_connect_params(socket) do
                nil -> %{}
                v -> v
              end

            timezone = Map.get(connect_params, "timezone", "America/Los_Angeles")

            # Calculate price breakdown
            price_breakdown = calculate_price_breakdown(booking)

            {:ok,
             socket
             |> assign(:booking, booking)
             |> assign(:payment, payment)
             |> assign(:timezone, timezone)
             |> assign(:price_breakdown, price_breakdown)
             |> assign(:page_title, "Booking Confirmation")}
          end
      end
    end
  end

  @impl true
  def handle_event("view-bookings", _params, socket) do
    property = socket.assigns.booking.property
    path = if property == :tahoe, do: ~p"/bookings/tahoe", else: ~p"/bookings/clear-lake"
    {:noreply, redirect(socket, to: path)}
  end

  @impl true
  def handle_event("go-home", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10 max-w-screen-lg mx-auto px-4">
      <div class="max-w-xl mx-auto pb-10">
        <div class="mb-6">
          <div class="text-center mb-6">
            <div class="text-green-500 mb-4">
              <.icon name="hero-check-circle" class="w-16 h-16 mx-auto" />
            </div>
            <h1 class="text-3xl font-bold text-zinc-900 mb-2">Booking Confirmed!</h1>
            <p class="text-zinc-600">
              Your booking has been successfully confirmed. You'll receive a confirmation email shortly.
            </p>
          </div>
        </div>

        <div class="space-y-6">
          <!-- Booking Summary -->
          <div>
            <div class="bg-white rounded-lg border border-zinc-200 p-6">
              <h2 class="text-xl font-semibold text-zinc-900 mb-4">Booking Summary</h2>

              <div class="space-y-4">
                <div>
                  <div class="text-sm text-zinc-600">Booking Reference</div>
                  <div class="font-medium text-zinc-900 font-mono"><%= @booking.reference_id %></div>
                </div>

                <div>
                  <div class="text-sm text-zinc-600">Property</div>
                  <div class="font-medium text-zinc-900">
                    <%= format_property_name(@booking.property) %>
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
                  <div class="font-medium text-zinc-900">
                    <%= @booking.guests_count %>
                    <%= if @booking.children_count > 0 do %>
                      (<%= @booking.children_count %> children)
                    <% end %>
                  </div>
                </div>

                <div>
                  <div class="text-sm text-zinc-600">Booking Mode</div>
                  <div class="font-medium text-zinc-900">
                    <%= if @booking.booking_mode == :buyout do %>
                      Full Buyout
                    <% else %>
                      <%= if @booking.booking_mode == :room do %>
                        Per Room
                      <% else %>
                        Per Guest
                      <% end %>
                    <% end %>
                  </div>
                </div>

                <%= if Ecto.assoc_loaded?(@booking.rooms) && length(@booking.rooms) > 0 do %>
                  <div>
                    <div class="text-sm text-zinc-600">
                      <%= if length(@booking.rooms) == 1, do: "Room", else: "Rooms" %>
                    </div>
                    <div class="font-medium text-zinc-900">
                      <%= Enum.map_join(@booking.rooms, ", ", fn room -> room.name end) %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
          <!-- Payment Summary -->
          <%= if @payment do %>
            <div>
              <div class="bg-white rounded-lg border border-zinc-200 p-6">
                <h2 class="text-xl font-semibold text-zinc-900 mb-4">Payment Summary</h2>

                <div class="space-y-3">
                  <%= if @price_breakdown do %>
                    <%= render_price_breakdown(assigns) %>
                  <% end %>

                  <div class="flex justify-between text-sm">
                    <span class="text-zinc-600">Payment Method</span>
                    <span class="text-zinc-900">
                      <%= get_payment_method_description(@payment) %>
                    </span>
                  </div>

                  <div class="flex justify-between text-sm">
                    <span class="text-zinc-600">Payment Date</span>
                    <span class="text-zinc-900">
                      <%= format_datetime(@payment.payment_date, @timezone) %>
                    </span>
                  </div>

                  <div class="border-t border-zinc-200 pt-3">
                    <div class="flex justify-between items-center">
                      <span class="text-lg font-semibold text-zinc-900">Total Paid</span>
                      <span class="text-2xl font-bold text-zinc-900">
                        <%= MoneyHelper.format_money!(@payment.amount) %>
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
          <!-- Action Buttons -->
          <div class="flex flex-col sm:flex-row gap-4">
            <.button phx-click="view-bookings" class="flex-1 bg-blue-600 hover:bg-blue-700 text-white">
              View My Bookings
            </.button>
            <.button phx-click="go-home" class="flex-1 bg-zinc-200 text-zinc-800 hover:bg-zinc-300">
              Back to Home
            </.button>
          </div>
          <!-- Additional Info -->
          <div class="text-center">
            <p class="text-sm text-zinc-500">
              Need help? Contact us at
              <a href="mailto:info@ysc.org" class="text-blue-600 hover:text-blue-500">
                info@ysc.org
              </a>
            </p>
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
      <%= if @price_breakdown && is_map(@price_breakdown) do %>
        <%= if @price_breakdown["rooms"] && is_list(@price_breakdown["rooms"]) do %>
          <!-- Multiple rooms -->
          <%= for room_item <- @price_breakdown["rooms"] do %>
            <div class="flex justify-between text-sm">
              <span class="text-zinc-600">
                <%= if room_item["room_name"] do %>
                  <%= room_item["room_name"] %>:
                <% end %>
                <%= @price_breakdown["nights"] || 0 %> night(s)
                <%= if @price_breakdown["guests_count"] do %>
                  × <%= @price_breakdown["guests_count"] %> guest(s)
                <% end %>
                <%= if @price_breakdown["children_count"] && @price_breakdown["children_count"] > 0 do %>
                  × <%= @price_breakdown["children_count"] %> child(ren)
                <% end %>
              </span>
              <span class="text-zinc-900">
                <%= if room_item["total"] do %>
                  <%= MoneyHelper.format_money!(
                    Money.new(room_item["total"]["currency"], room_item["total"]["amount"])
                  ) %>
                <% end %>
              </span>
            </div>
          <% end %>
        <% else %>
          <!-- Single room (legacy format) -->
          <div class="flex justify-between text-sm">
            <span class="text-zinc-600">
              <%= @price_breakdown["nights"] || 0 %> night(s)
              <%= if @price_breakdown["guests_count"] do %>
                × <%= @price_breakdown["guests_count"] %> guest(s)
              <% end %>
              <%= if @price_breakdown["children_count"] && @price_breakdown["children_count"] > 0 do %>
                × <%= @price_breakdown["children_count"] %> child(ren)
              <% end %>
            </span>
            <span class="text-zinc-900">
              <%= if @price_breakdown["total"] do %>
                <%= MoneyHelper.format_money!(
                  Money.new(
                    @price_breakdown["total"]["currency"],
                    @price_breakdown["total"]["amount"]
                  )
                ) %>
              <% end %>
            </span>
          </div>
        <% end %>
      <% end %>
    <% end %>
    """
  end

  ## Private Functions

  defp handle_stripe_redirect(params, booking, socket) do
    redirect_status = Map.get(params, "redirect_status")
    payment_intent_id = Map.get(params, "payment_intent")

    case {redirect_status, payment_intent_id} do
      {"succeeded", payment_intent_id} when not is_nil(payment_intent_id) ->
        # Payment succeeded via redirect - process it
        case process_payment_from_redirect(booking, payment_intent_id) do
          {:ok, _confirmed_booking} ->
            socket
            |> put_flash(:info, "Payment successful! Your booking is confirmed.")

          {:error, :already_processed} ->
            # Payment was already processed (maybe via webhook or client-side)
            socket
            |> put_flash(:info, "Your booking is confirmed.")

          {:error, reason} ->
            Logger.error("Failed to process payment from redirect",
              booking_id: booking.id,
              payment_intent_id: payment_intent_id,
              error: reason
            )

            socket
            |> put_flash(
              :error,
              "Payment was successful, but there was an issue confirming your booking. Please contact support."
            )
        end

      {"failed", _payment_intent_id} ->
        socket
        |> put_flash(
          :error,
          "Payment failed. Please try again or contact support if the problem persists."
        )

      _ ->
        # No redirect parameters or unknown status
        socket
    end
  end

  defp process_payment_from_redirect(booking, payment_intent_id) do
    # Check if booking is already confirmed (avoid double processing)
    if booking.status == :complete do
      {:error, :already_processed}
    else
      # Use the same logic as checkout page
      process_payment_success(booking, payment_intent_id)
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
            {:ok, _payment} ->
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

  defp cents_to_money(cents, currency)

  defp cents_to_money(cents, currency) when is_integer(cents) do
    cents_decimal = Decimal.new(cents)
    dollars = Decimal.div(cents_decimal, Decimal.new(100))
    Money.new(currency, dollars)
  end

  defp cents_to_money(_, _), do: Money.new(0, :USD)

  defp get_booking_payment(booking) do
    # Find the payment via ledger entries
    # Note: We filter by amount > 0 in Elixir since Money comparison in queries is complex
    entries =
      from(e in Ysc.Ledgers.LedgerEntry,
        where: e.related_entity_type == ^:booking,
        where: e.related_entity_id == ^booking.id,
        preload: [:payment],
        order_by: [desc: e.inserted_at]
      )
      |> Repo.all()

    # Filter for positive amounts and get the first one
    entry =
      entries
      |> Enum.find(fn e ->
        e.amount && Money.positive?(e.amount)
      end)

    if entry && entry.payment do
      Repo.preload(entry.payment, [:payment_method])
    else
      nil
    end
  end

  defp calculate_price_breakdown(booking) do
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
            %{
              nights: nights,
              price_per_night: Money.div(total, nights) |> elem(1)
            }

          _ ->
            nil
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

            %{
              nights: nights,
              guests_count: booking.guests_count,
              price_per_guest_per_night: price_per_guest_per_night
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp get_payment_method_description(payment) do
    case payment.payment_method do
      nil ->
        "Credit Card (Stripe)"

      payment_method ->
        case payment_method.type do
          :card ->
            if payment_method.last_four do
              brand = payment_method.display_brand || "Card"
              "#{String.capitalize(brand)} ending in #{payment_method.last_four}"
            else
              "Credit Card"
            end

          :bank_account ->
            if payment_method.last_four do
              bank_name = payment_method.bank_name || "Bank"
              "#{bank_name} Account ending in #{payment_method.last_four}"
            else
              "Bank Account"
            end

          _ ->
            "Payment Method"
        end
    end
  end

  defp format_property_name(:tahoe), do: "Lake Tahoe"
  defp format_property_name(:clear_lake), do: "Clear Lake"
  defp format_property_name(_), do: "Unknown"

  # Timezone-aware formatting functions
  defp format_date(%Date{} = date, _timezone) do
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
end
