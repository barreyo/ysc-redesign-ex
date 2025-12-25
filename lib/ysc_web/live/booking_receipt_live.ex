defmodule YscWeb.BookingReceiptLive do
  use YscWeb, :live_view

  alias Ysc.Bookings
  alias Ysc.Bookings.{Booking, BookingLocker, PendingRefund}
  alias Ysc.Ledgers.Refund
  alias Ysc.MoneyHelper
  alias Ysc.Repo
  require Logger
  import Ecto.Query
  alias Phoenix.LiveView.JS

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

            # Check if booking can be cancelled
            can_cancel = can_cancel_booking?(booking)

            # Get refund policy info for cancellation
            refund_info = get_refund_info(booking)

            # Check if confetti should be shown (only when coming from payment)
            # Show confetti if:
            # 1. URL has confetti=true parameter (from checkout page redirect)
            # 2. URL has redirect_status=succeeded (from Stripe redirect)
            show_confetti =
              Map.get(params, "confetti") == "true" ||
                Map.get(params, "redirect_status") == "succeeded"

            Logger.debug(
              "Confetti check: params=#{inspect(params)}, show_confetti=#{show_confetti}"
            )

            # Get door code if booking is within 48 hours of check-in or currently active
            # Don't show door code for cancelled bookings
            {door_code, show_door_code} =
              if booking.status == :canceled do
                {nil, false}
              else
                get_door_code_for_booking(booking)
              end

            # Get refund information if booking is cancelled
            refund_data = get_refund_data_for_booking(booking, payment)

            {:ok,
             socket
             |> assign(:booking, booking)
             |> assign(:payment, payment)
             |> assign(:timezone, timezone)
             |> assign(:price_breakdown, price_breakdown)
             |> assign(:user_first_name, user.first_name || "Member")
             |> assign(:can_cancel, can_cancel)
             |> assign(:refund_info, refund_info)
             |> assign(:show_cancel_modal, false)
             |> assign(:cancel_reason, "")
             |> assign(:show_confetti, show_confetti)
             |> assign(:door_code, door_code)
             |> assign(:show_door_code, show_door_code)
             |> assign(:refund_data, refund_data)
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
  def handle_event("show-cancel-modal", _params, socket) do
    {:noreply, assign(socket, :show_cancel_modal, true)}
  end

  @impl true
  def handle_event("hide-cancel-modal", _params, socket) do
    {:noreply, assign(socket, :show_cancel_modal, false)}
  end

  @impl true
  def handle_event("update-cancel-reason", %{"reason" => reason}, socket) do
    {:noreply, assign(socket, :cancel_reason, reason)}
  end

  @impl true
  def handle_event("update-cancel-reason", %{"value" => value}, socket) do
    {:noreply, assign(socket, :cancel_reason, value)}
  end

  @impl true
  def handle_event("confirm-cancel", %{"reason" => reason}, socket) do
    booking = socket.assigns.booking

    case Bookings.cancel_booking(booking, Date.utc_today(), reason) do
      {:ok, _canceled_booking, refund_amount, refund_result} ->
        # Check if refund_result is a PendingRefund (partial refund) or LedgerTransaction (full refund)
        is_pending_refund =
          case refund_result do
            %Ysc.Bookings.PendingRefund{} -> true
            _ -> false
          end

        refund_message =
          if Money.positive?(refund_amount) do
            if is_pending_refund do
              "Booking cancelled. Your refund of #{MoneyHelper.format_money!(refund_amount)} is pending admin review and will be processed once approved."
            else
              "Booking cancelled. A refund of #{MoneyHelper.format_money!(refund_amount)} will be processed."
            end
          else
            "Booking cancelled. No refund is available based on the cancellation policy."
          end

        {:noreply,
         socket
         |> assign(:show_cancel_modal, false)
         |> put_flash(:info, refund_message)
         |> redirect(to: ~p"/bookings/#{booking.id}/receipt")}

      {:error, reason} ->
        error_message =
          case reason do
            {:payment_not_found, _} ->
              "Unable to process cancellation: payment not found."

            {:calculation_failed, _} ->
              "Unable to calculate refund amount."

            {:refund_failed, _} ->
              "Booking cancelled but refund processing failed. Please contact support."

            {:pending_refund_failed, _} ->
              "Booking cancelled but could not create pending refund. Please contact support."

            {:cancellation_failed, _} ->
              "Failed to cancel booking. Please try again or contact support."

            _ ->
              "Failed to cancel booking. Please try again or contact support."
          end

        {:noreply,
         socket
         |> assign(:show_cancel_modal, false)
         |> put_flash(:error, error_message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="booking-receipt"
      phx-hook="Confetti"
      data-show-confetti={if @show_confetti, do: "true", else: "false"}
      class="py-8 lg:py-10 max-w-screen-xl mx-auto px-4"
    >
      <!-- Header -->
      <div class="mb-10 flex flex-col md:flex-row md:items-end justify-between gap-4 border-b border-zinc-100 pb-8">
        <div>
          <%= if @booking.status == :canceled do %>
            <div class="flex items-center gap-2 text-red-600 mb-2">
              <.icon name="hero-x-circle" class="w-6 h-6" />
              <span class="font-bold uppercase tracking-wider text-sm">Reservation Cancelled</span>
            </div>
            <h1 class="text-4xl font-bold text-zinc-900">
              Booking Cancelled
            </h1>
            <p class="text-zinc-500 mt-2 text-lg">
              Your booking at <strong><%= format_property_name(@booking.property) %></strong>
              has been cancelled.
              <%= if @refund_data && @refund_data.total_refunded do %>
                <%= if @refund_data.has_pending_refund do %>
                  A refund of
                  <strong><%= MoneyHelper.format_money!(@refund_data.total_refunded) %></strong>
                  is pending admin review.
                <% else %>
                  A refund of
                  <strong><%= MoneyHelper.format_money!(@refund_data.total_refunded) %></strong>
                  has been processed.
                <% end %>
              <% else %>
                No refund is available based on the cancellation policy.
              <% end %>
            </p>
          <% else %>
            <div class="flex items-center gap-2 text-green-600 mb-2">
              <.icon name="hero-check-circle-solid" class="w-6 h-6" />
              <span class="font-bold uppercase tracking-wider text-sm">Reservation Confirmed</span>
            </div>
            <h1 class="text-4xl font-bold text-zinc-900">
              See you at the Cabin, <%= @user_first_name %>!
            </h1>
            <p class="text-zinc-500 mt-2 text-lg">
              Your stay at <strong><%= format_property_name(@booking.property) %></strong> is all set.
              We've sent a copy of these details to your email.
            </p>
          <% end %>
        </div>
        <div class="text-left md:text-right">
          <p class="text-xs font-bold text-zinc-400 uppercase tracking-widest">Booking Reference</p>
          <p class="font-mono text-lg font-semibold text-zinc-900 whitespace-nowrap">
            <%= @booking.reference_id %>
          </p>
        </div>
      </div>
      <!-- Door Code Banner (if applicable) -->
      <%= if @show_door_code && @door_code do %>
        <div class={[
          "mb-8 rounded-2xl p-8 shadow-xl border-4",
          if(@booking.property == :clear_lake,
            do: "bg-gradient-to-r from-teal-600 to-teal-700 border-teal-400 text-white",
            else: "bg-gradient-to-r from-blue-600 to-blue-700 border-blue-400 text-white"
          )
        ]}>
          <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-6">
            <div class="flex-1">
              <div class="flex items-center gap-3 mb-3">
                <.icon
                  name="hero-key"
                  class={[
                    "w-8 h-8",
                    if(@booking.property == :clear_lake, do: "text-teal-200", else: "text-blue-200")
                  ]}
                />
                <h2 class="text-2xl font-bold">Your Door Code</h2>
              </div>
              <p class={[
                "text-sm md:text-base",
                if(@booking.property == :clear_lake, do: "text-teal-100", else: "text-blue-100")
              ]}>
                <%= if booking_is_active?(@booking) do %>
                  Your booking is currently active. Use this code to access the property.
                <% else %>
                  Your check-in is approaching. Save this code — you'll need it to access the property.
                <% end %>
              </p>
            </div>
            <div class="flex-shrink-0">
              <div class="bg-white/20 backdrop-blur-sm rounded-xl px-8 py-6 border-2 border-white/30">
                <p class={[
                  "text-xs font-bold uppercase tracking-widest mb-2 text-center",
                  if(@booking.property == :clear_lake, do: "text-teal-200", else: "text-blue-200")
                ]}>
                  Door Code
                </p>
                <p class="text-5xl font-mono font-black text-white text-center tracking-wider">
                  <%= @door_code.code %>
                </p>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-10">
        <!-- Left Column: Main Content -->
        <div class="lg:col-span-2 space-y-8">
          <%= if @booking.status == :canceled do %>
            <!-- Cancelled Booking Notice -->
            <div class="bg-red-50 border-2 border-red-300 rounded-xl p-6 mb-6">
              <div class="flex items-start gap-4">
                <.icon
                  name="hero-exclamation-triangle"
                  class="w-8 h-8 text-red-600 flex-shrink-0 mt-1"
                />
                <div class="flex-1">
                  <h3 class="text-lg font-bold text-red-900 mb-2">This Booking Has Been Cancelled</h3>
                  <p class="text-sm text-red-800 leading-relaxed">
                    This reservation is no longer active. You will not have access to the property for these dates.
                    <%= if @refund_data && @refund_data.total_refunded do %>
                      Your refund information is shown in the payment summary on the right.
                    <% end %>
                  </p>
                </div>
              </div>
            </div>
          <% end %>
          <!-- Stay Details Card -->
          <div class={[
            "rounded-lg border overflow-hidden",
            if(@booking.status == :canceled,
              do: "bg-zinc-100 border-zinc-300 opacity-60",
              else: "bg-zinc-50 border-zinc-200"
            )
          ]}>
            <!-- Property Image -->
            <div class={[
              "h-48 bg-zinc-200 relative",
              if(@booking.status == :canceled, do: "opacity-50 grayscale")
            ]}>
              <img
                src={get_property_thumbnail(@booking.property)}
                alt={format_property_name(@booking.property)}
                class="w-full h-full object-cover"
              />
              <%= if @booking.status == :canceled do %>
                <div class="absolute inset-0 bg-red-500/20 flex items-center justify-center">
                  <div class="bg-white/90 rounded-lg px-6 py-3 shadow-lg">
                    <p class="text-red-700 font-bold text-lg uppercase tracking-wider">Cancelled</p>
                  </div>
                </div>
              <% end %>
              <div class="absolute inset-0 bg-gradient-to-t from-black/40 to-transparent flex items-end p-6">
                <div class="flex items-center justify-between w-full">
                  <h2 class={[
                    "text-xl font-bold flex items-center gap-2",
                    if(@booking.status == :canceled,
                      do: "text-zinc-300 line-through",
                      else: "text-white"
                    )
                  ]}>
                    <.icon name="hero-information-circle" class="w-8 h-8" /> Stay Details
                  </h2>
                  <span class={[
                    "text-sm font-medium px-3 py-1 rounded-full",
                    if(@booking.status == :canceled,
                      do: "bg-zinc-300 text-zinc-600",
                      else: "bg-blue-100 text-blue-700"
                    )
                  ]}>
                    <%= Date.diff(@booking.checkout_date, @booking.checkin_date) %> <%= if Date.diff(
                                                                                             @booking.checkout_date,
                                                                                             @booking.checkin_date
                                                                                           ) == 1,
                                                                                           do:
                                                                                             "Night",
                                                                                           else:
                                                                                             "Nights" %>
                  </span>
                </div>
              </div>
            </div>
            <div class="p-8 grid grid-cols-1 md:grid-cols-3 gap-8">
              <div>
                <p class={[
                  "text-xs font-bold uppercase mb-1",
                  if(@booking.status == :canceled, do: "text-zinc-500", else: "text-zinc-400")
                ]}>
                  Check-in
                </p>
                <p class={[
                  "text-xl font-bold",
                  if(@booking.status == :canceled,
                    do: "text-zinc-500 line-through",
                    else: "text-zinc-900"
                  )
                ]}>
                  <%= format_date(@booking.checkin_date, @timezone) %>
                </p>
                <p class={[
                  "text-sm",
                  if(@booking.status == :canceled, do: "text-zinc-400", else: "text-zinc-500")
                ]}>
                  After 3:00 PM
                </p>
              </div>
              <div>
                <p class={[
                  "text-xs font-bold uppercase mb-1",
                  if(@booking.status == :canceled, do: "text-zinc-500", else: "text-zinc-400")
                ]}>
                  Check-out
                </p>
                <p class={[
                  "text-xl font-bold",
                  if(@booking.status == :canceled,
                    do: "text-zinc-500 line-through",
                    else: "text-zinc-900"
                  )
                ]}>
                  <%= format_date(@booking.checkout_date, @timezone) %>
                </p>
                <p class={[
                  "text-sm",
                  if(@booking.status == :canceled, do: "text-zinc-400", else: "text-zinc-500")
                ]}>
                  Before 11:00 AM
                </p>
              </div>
              <div>
                <p class={[
                  "text-xs font-bold uppercase mb-1",
                  if(@booking.status == :canceled, do: "text-zinc-500", else: "text-zinc-400")
                ]}>
                  Room Assignment
                </p>
                <p class={[
                  "text-xl font-bold",
                  if(@booking.status == :canceled,
                    do: "text-zinc-500 line-through",
                    else: "text-zinc-900"
                  )
                ]}>
                  <%= if Ecto.assoc_loaded?(@booking.rooms) && length(@booking.rooms) > 0 do %>
                    <%= Enum.map_join(@booking.rooms, ", ", fn room -> room.name end) %>
                  <% else %>
                    <%= if @booking.booking_mode == :buyout do %>
                      Full Buyout
                    <% else %>
                      Per Guest
                    <% end %>
                  <% end %>
                </p>
                <p
                  :if={@booking.booking_mode != :buyout}
                  class={[
                    "text-sm",
                    if(@booking.status == :canceled, do: "text-zinc-400", else: "text-zinc-500")
                  ]}
                >
                  <%= @booking.guests_count %> <%= if @booking.guests_count == 1,
                    do: "Adult",
                    else: "Adults" %>
                  <%= if @booking.children_count > 0 do %>
                    , <%= @booking.children_count %> <%= if @booking.children_count == 1,
                      do: "Child",
                      else: "Children" %>
                  <% end %>
                </p>
              </div>
            </div>
          </div>
          <!-- Utility Cards (Hidden for cancelled bookings) -->
          <%= if @booking.status != :canceled do %>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <!-- Cabin Access -->
              <div class="p-6 bg-white border border-zinc-200 rounded-lg">
                <h3 class="font-bold text-zinc-900 mb-3 flex items-center gap-2">
                  <.icon name="hero-key" class="w-5 h-5" /> Cabin Access
                </h3>
                <p class="text-sm text-zinc-600 mb-4">
                  Door codes and key instructions are sent via email 24 hours before your check-in.
                </p>
                <a
                  href={get_cabin_guide_url(@booking.property)}
                  class="text-sm font-semibold text-blue-600 hover:underline"
                >
                  View Arrival Guide →
                </a>
              </div>
              <!-- Cabin Rules -->
              <div class="p-6 bg-white border border-zinc-200 rounded-lg">
                <h3 class="font-bold text-zinc-900 mb-3 flex items-center gap-2">
                  <.icon name="hero-document-check" class="w-5 h-5" /> Cabin Rules
                </h3>
                <p class="text-sm text-zinc-600 mb-4">
                  Reminder: Please bring your own linens and ensure the kitchen is cleaned before departure.
                </p>
                <a
                  href={get_cabin_guide_url(@booking.property)}
                  class="text-sm font-semibold text-blue-600 hover:underline"
                >
                  Read House Rules →
                </a>
              </div>
            </div>
          <% end %>
        </div>
        <!-- Right Column: Sidebar -->
        <aside class="space-y-6">
          <!-- Payment Summary -->
          <%= if @payment do %>
            <div class={[
              "rounded-lg p-8 shadow-xl",
              if(@booking.status == :canceled,
                do: "bg-red-50 border-2 border-red-200",
                else: "bg-zinc-900 text-white"
              )
            ]}>
              <h3 class={[
                "text-xs font-bold uppercase tracking-widest mb-6",
                if(@booking.status == :canceled,
                  do: "text-red-700",
                  else: "text-zinc-400"
                )
              ]}>
                <%= if @booking.status == :canceled,
                  do: "Payment & Refund Summary",
                  else: "Payment Summary" %>
              </h3>
              <div class={[
                "space-y-4 text-sm",
                if(@booking.status == :canceled, do: "text-zinc-900", else: "")
              ]}>
                <div class="flex justify-between">
                  <span class={
                    if(@booking.status == :canceled, do: "text-zinc-600", else: "text-zinc-400")
                  }>
                    Total Paid
                  </span>
                  <span class={[
                    "font-bold text-xl",
                    if(@booking.status == :canceled,
                      do: "text-zinc-900",
                      else: "text-blue-400"
                    )
                  ]}>
                    <%= MoneyHelper.format_money!(@payment.amount) %>
                  </span>
                </div>
                <%= if @booking.status == :canceled && @refund_data do %>
                  <%= if @refund_data.total_refunded do %>
                    <div class="flex justify-between border-t border-red-200 pt-4">
                      <span class="text-zinc-600">Refunded</span>
                      <span class="font-bold text-green-600 text-xl">
                        <%= MoneyHelper.format_money!(@refund_data.total_refunded) %>
                      </span>
                    </div>
                    <%= if @refund_data.has_pending_refund do %>
                      <div class="bg-amber-50 border border-amber-200 rounded-lg p-3 mt-2">
                        <div class="flex items-start gap-2">
                          <.icon
                            name="hero-clock"
                            class="w-4 h-4 text-amber-600 mt-0.5 flex-shrink-0"
                          />
                          <p class="text-xs text-amber-800">
                            <strong>Pending Review:</strong>
                            This refund is pending admin approval and will be processed once approved.
                          </p>
                        </div>
                      </div>
                    <% end %>
                    <%= if @refund_data.processed_refunds && length(@refund_data.processed_refunds) > 0 do %>
                      <div class="border-t border-red-200 pt-4 space-y-2">
                        <p class="text-xs font-semibold text-zinc-600 uppercase tracking-wider">
                          Refund Details
                        </p>
                        <%= for refund <- @refund_data.processed_refunds do %>
                          <div class="flex justify-between text-xs">
                            <span class="text-zinc-500">
                              <%= MoneyHelper.format_money!(refund.amount) %>
                              <%= if refund.reason do %>
                                <span class="text-zinc-400">
                                  • <%= String.slice(refund.reason, 0, 30) %><%= if String.length(
                                                                                      refund.reason
                                                                                    ) > 30, do: "..." %>
                                </span>
                              <% end %>
                            </span>
                            <span class={[
                              "font-medium",
                              if(refund.status == :completed,
                                do: "text-green-600",
                                else: "text-amber-600"
                              )
                            ]}>
                              <%= if refund.status == :completed,
                                do: "Processed",
                                else: String.capitalize(Atom.to_string(refund.status)) %>
                            </span>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                    <div class="flex justify-between border-t-2 border-red-300 pt-4 mt-4">
                      <span class="font-semibold text-zinc-900">Net Amount</span>
                      <span class="font-bold text-red-600 text-xl">
                        <%= case Money.sub(@payment.amount, @refund_data.total_refunded) do
                          {:ok, net} -> MoneyHelper.format_money!(net)
                          _ -> MoneyHelper.format_money!(@payment.amount)
                        end %>
                      </span>
                    </div>
                  <% else %>
                    <div class="bg-zinc-100 border border-zinc-300 rounded-lg p-3 mt-2">
                      <p class="text-xs text-zinc-700">
                        No refund is available based on the cancellation policy.
                      </p>
                    </div>
                  <% end %>
                <% end %>
                <div class={[
                  "flex justify-between",
                  if(@booking.status == :canceled,
                    do: "border-t border-red-200 pt-4",
                    else: "border-t border-zinc-800 pt-4"
                  )
                ]}>
                  <span class={
                    if(@booking.status == :canceled, do: "text-zinc-600", else: "text-zinc-400")
                  }>
                    Method
                  </span>
                  <span><%= get_payment_method_description(@payment) %></span>
                </div>
                <div class="flex justify-between">
                  <span class={
                    if(@booking.status == :canceled, do: "text-zinc-600", else: "text-zinc-400")
                  }>
                    Date
                  </span>
                  <span><%= format_payment_date(@payment.payment_date, @timezone) %></span>
                </div>
              </div>
            </div>
          <% end %>
          <!-- Action Buttons -->
          <div class="space-y-3">
            <button
              phx-click="view-bookings"
              class="w-full py-4 bg-zinc-100 text-zinc-800 rounded-lg font-bold hover:bg-zinc-200 transition-all"
            >
              Manage All My Bookings
            </button>
            <%= if @booking.status != :canceled && @can_cancel do %>
              <button
                phx-click="show-cancel-modal"
                class="w-full py-4 bg-red-50 text-red-700 rounded-lg font-bold hover:bg-red-100 transition-all border border-red-200 flex items-center justify-center gap-2"
              >
                <.icon name="hero-x-circle" class="w-5 h-5" /> Cancel Reservation
              </button>
            <% end %>
            <button
              phx-click="go-home"
              class="w-full py-4 border-2 border-zinc-100 text-zinc-500 rounded-lg font-bold hover:bg-zinc-50 transition-all"
            >
              Return to Dashboard
            </button>
          </div>
        </aside>
      </div>
      <!-- Cancel Booking Modal -->
      <%= if @show_cancel_modal do %>
        <.modal id="cancel-booking-modal" on_cancel={JS.push("hide-cancel-modal")} show>
          <h2 class="text-2xl font-semibold leading-8 text-zinc-800 mb-6">
            Cancel Booking
          </h2>

          <div class="space-y-4">
            <p class="text-zinc-600">
              Are you sure you want to cancel this booking? This action cannot be undone.
            </p>
            <!-- Refund Information -->
            <%= if @refund_info && @refund_info.estimated_refund do %>
              <div class="bg-blue-50 border border-blue-200 rounded-lg p-4 space-y-3">
                <div class="flex items-center gap-2 text-blue-800">
                  <.icon name="hero-information-circle" class="w-5 h-5" />
                  <p class="font-semibold">Estimated Refund</p>
                </div>
                <div class="pl-7 space-y-2">
                  <div class="flex justify-between items-baseline">
                    <span class="text-sm text-blue-700">Original Payment:</span>
                    <span class="text-sm font-medium text-blue-900">
                      <%= if @payment do %>
                        <%= MoneyHelper.format_money!(@payment.amount) %>
                      <% else %>
                        —
                      <% end %>
                    </span>
                  </div>
                  <div class="flex justify-between items-baseline">
                    <span class="text-sm text-blue-700">Estimated Refund:</span>
                    <span class="text-lg font-bold text-blue-900">
                      <%= MoneyHelper.format_money!(@refund_info.estimated_refund) %>
                    </span>
                  </div>
                  <%= if @refund_info.applied_rule do %>
                    <% refund_percent =
                      Decimal.to_float(@refund_info.applied_rule.refund_percentage)
                      |> Float.round(0)
                      |> trunc() %>
                    <p class="text-xs text-blue-600 mt-2 pt-2 border-t border-blue-200">
                      Based on cancellation policy: <%= refund_percent %>% refund if cancelled <%= @refund_info.applied_rule.days_before_checkin %> days or more before check-in.
                    </p>
                  <% else %>
                    <p class="text-xs text-blue-600 mt-2 pt-2 border-t border-blue-200">
                      Full refund based on cancellation policy.
                    </p>
                  <% end %>
                </div>
              </div>
            <% else %>
              <div class="bg-amber-50 border border-amber-200 rounded-lg p-4">
                <div class="flex items-center gap-2 text-amber-800">
                  <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
                  <p class="font-semibold">No Refund Available</p>
                </div>
                <p class="text-sm text-amber-700 mt-2 pl-7">
                  Based on the cancellation policy and timing of your cancellation, no refund is available for this booking.
                </p>
              </div>
            <% end %>

            <.simple_form for={%{}} id="cancel-booking-form" phx-submit="confirm-cancel">
              <.input
                type="textarea"
                name="reason"
                label="Cancellation Reason (Optional)"
                value={@cancel_reason}
                phx-blur="update-cancel-reason"
                phx-debounce="300"
                rows="3"
              />

              <:actions>
                <.button type="submit" color="red" phx-disable-with="Cancelling...">
                  Cancel Booking
                </.button>
                <.button
                  type="button"
                  phx-click="hide-cancel-modal"
                  class="bg-zinc-200 text-zinc-800 hover:bg-zinc-300"
                >
                  Keep Booking
                </.button>
              </:actions>
            </.simple_form>
          </div>
        </.modal>
      <% end %>
      <!-- Footer Note -->
      <div class="mt-12 pt-8 border-t border-zinc-100">
        <p class="text-sm text-zinc-500 text-center">
          The YSC is run by members like you. If you have questions about your stay, contact the <%= format_property_name(
            @booking.property
          ) %> Cabin Master at
          <a
            href={"mailto:#{get_cabin_master_email(@booking.property)}"}
            class="text-blue-600 hover:text-blue-500 underline"
          >
            <%= get_cabin_master_email(@booking.property) %>
          </a>
          .
        </p>
      </div>
    </div>
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
    # Payment entries are debit entries to stripe_account
    entry =
      from(e in Ysc.Ledgers.LedgerEntry,
        join: a in Ysc.Ledgers.LedgerAccount,
        on: e.account_id == a.id,
        where: e.related_entity_type == ^:booking,
        where: e.related_entity_id == ^booking.id,
        where: e.debit_credit == "debit",
        where: a.name == "stripe_account",
        preload: [:payment],
        order_by: [desc: e.inserted_at],
        limit: 1
      )
      |> Repo.one()

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

  defp format_property_name(:tahoe), do: "Lake Tahoe Cabin"
  defp format_property_name(:clear_lake), do: "Clear Lake Cabin"
  defp format_property_name(_), do: "Unknown"

  defp get_property_thumbnail(property) do
    case property do
      :tahoe -> ~p"/images/tahoe/tahoe_cabin_main.webp"
      :clear_lake -> ~p"/images/clear_lake/clear_lake_dock.webp"
      _ -> ~p"/images/ysc_logo.png"
    end
  end

  defp get_cabin_guide_url(property) do
    case property do
      :tahoe -> ~p"/bookings/tahoe?tab=information"
      :clear_lake -> ~p"/bookings/clear-lake?tab=information"
      _ -> ~p"/"
    end
  end

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

  defp format_datetime(_, _timezone), do: "—"

  defp format_payment_date(%DateTime{} = datetime, timezone) do
    format_datetime(datetime, timezone)
  end

  defp format_payment_date(%Date{} = date, timezone) do
    format_date(date, timezone)
  end

  defp format_payment_date(_, _timezone), do: "—"

  defp get_cabin_master_email(property) do
    case property do
      :tahoe -> Ysc.EmailConfig.tahoe_email()
      :clear_lake -> Ysc.EmailConfig.clear_lake_email()
      _ -> "info@ysc.org"
    end
  end

  defp can_cancel_booking?(booking) do
    # Can cancel if booking is complete or hold, and check-in is in the future
    # OR if check-in is today (in PST) and it's before 3PM PST
    today_pst = get_today_pst()

    booking.status in [:complete, :hold] &&
      (Date.compare(booking.checkin_date, today_pst) == :gt ||
         (Date.compare(booking.checkin_date, today_pst) == :eq &&
            before_checkin_time_today?()))
  end

  defp get_today_pst do
    DateTime.now!("America/Los_Angeles") |> DateTime.to_date()
  end

  defp before_checkin_time_today? do
    # Check if current time (in PST) is before 3PM (15:00)
    now_pst = DateTime.now!("America/Los_Angeles")
    today_pst = DateTime.to_date(now_pst)
    checkin_time = ~T[15:00:00]
    checkin_datetime_today = DateTime.new!(today_pst, checkin_time, "America/Los_Angeles")
    DateTime.compare(now_pst, checkin_datetime_today) == :lt
  end

  defp get_refund_info(booking) do
    if can_cancel_booking?(booking) do
      case Bookings.calculate_refund(booking, Date.utc_today()) do
        {:ok, refund_amount, applied_rule} ->
          policy = Bookings.get_active_refund_policy(booking.property, booking.booking_mode)
          rules = if policy, do: policy.rules || [], else: []

          # If refund_amount is nil, it means full refund (no policy)
          # In that case, we need to get the payment amount
          estimated_refund =
            if is_nil(refund_amount) do
              case get_booking_payment(booking) do
                nil -> nil
                payment -> payment.amount
              end
            else
              refund_amount
            end

          %{
            estimated_refund: estimated_refund,
            applied_rule: applied_rule,
            policy_rules: rules
          }

        _ ->
          %{estimated_refund: nil, applied_rule: nil, policy_rules: []}
      end
    else
      nil
    end
  end

  defp get_door_code_for_booking(booking) do
    # Check if booking is currently active (today is between check-in and check-out)
    is_active = booking_is_active?(booking)

    # Check if booking is within 48 hours of check-in
    hours_until_checkin =
      if booking.checkin_date do
        checkin_datetime = DateTime.new!(booking.checkin_date, ~T[15:00:00], "Etc/UTC")
        now = DateTime.utc_now()
        DateTime.diff(checkin_datetime, now, :hour)
      else
        nil
      end

    within_48_hours =
      hours_until_checkin != nil && hours_until_checkin >= 0 && hours_until_checkin <= 48

    if is_active || within_48_hours do
      door_code = Bookings.get_active_door_code(booking.property)
      {door_code, true}
    else
      {nil, false}
    end
  end

  defp booking_is_active?(booking) do
    today = Date.utc_today()

    if booking.checkin_date && booking.checkout_date do
      Date.compare(today, booking.checkin_date) != :lt &&
        Date.compare(today, booking.checkout_date) == :lt
    else
      false
    end
  end

  defp get_refund_data_for_booking(booking, payment) do
    if booking.status == :canceled && payment do
      # Get processed refunds for this payment
      processed_refunds =
        from(r in Refund,
          where: r.payment_id == ^payment.id,
          order_by: [desc: r.inserted_at]
        )
        |> Repo.all()

      # Get pending refund for this booking
      pending_refund =
        from(pr in PendingRefund,
          where: pr.booking_id == ^booking.id,
          where: pr.status == :pending,
          order_by: [desc: pr.inserted_at],
          limit: 1
        )
        |> Repo.one()

      # Calculate total refunded amount
      processed_total =
        Enum.reduce(processed_refunds, Money.new(0, :USD), fn refund, acc ->
          case Money.add(acc, refund.amount) do
            {:ok, sum} -> sum
            _ -> acc
          end
        end)

      pending_amount =
        if pending_refund do
          # Use admin_refund_amount if set, otherwise use policy_refund_amount
          pending_refund.admin_refund_amount || pending_refund.policy_refund_amount
        else
          nil
        end

      total_refunded =
        if pending_amount do
          case Money.add(processed_total, pending_amount) do
            {:ok, total} -> total
            _ -> processed_total
          end
        else
          processed_total
        end

      %{
        processed_refunds: processed_refunds,
        pending_refund: pending_refund,
        total_refunded: if(Money.positive?(total_refunded), do: total_refunded, else: nil),
        has_pending_refund: not is_nil(pending_refund)
      }
    else
      nil
    end
  end
end
