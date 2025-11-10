defmodule YscWeb.OrderConfirmationLive do
  use YscWeb, :live_view

  alias Ysc.Tickets
  alias Ysc.Events

  @impl true
  def mount(%{"order_id" => order_id}, _session, socket) do
    case Tickets.get_ticket_order(order_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Order not found")
         |> redirect(to: ~p"/events")}

      ticket_order ->
        # Verify the order belongs to the current user
        if ticket_order.user_id == socket.assigns.current_user.id do
          # Load the event for display
          event = Events.get_event!(ticket_order.event_id)

          {:ok,
           socket
           |> assign(:ticket_order, ticket_order)
           |> assign(:event, event)
           |> assign(:page_title, "Order Confirmation")}
        else
          {:ok,
           socket
           |> put_flash(:error, "You don't have permission to view this order")
           |> redirect(to: ~p"/events")}
        end
    end
  end

  @impl true
  def handle_event("close", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/events/#{socket.assigns.event.id}")}
  end

  @impl true
  def handle_event("view-tickets", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/users/tickets")}
  end

  @impl true
  def handle_event("view-event", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/events/#{socket.assigns.event.id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen py-12">
      <div class="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8">
        <!-- Success Header -->
        <div class="text-center mb-8">
          <div class="text-green-500 mb-4">
            <.icon name="hero-check-circle" class="w-16 h-16 mx-auto" />
          </div>
          <h1 class="text-3xl font-bold text-zinc-900 mb-2">Order Confirmed!</h1>
          <p class="text-zinc-600">
            Your tickets have been successfully confirmed. You'll receive a confirmation email shortly.
          </p>
        </div>
        <!-- Order Details Card -->
        <div class="bg-white rounded-lg shadow-sm border border-zinc-200 mb-6">
          <div class="px-6 py-4 border-b border-zinc-200">
            <h2 class="text-lg font-semibold text-zinc-900">Order Details</h2>
          </div>
          <div class="px-6 py-4 space-y-4">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <dt class="text-sm font-medium text-zinc-500">Order ID</dt>
                <dd class="mt-1 text-sm text-zinc-900 font-mono">
                  <%= @ticket_order.reference_id %>
                </dd>
              </div>
              <div>
                <dt class="text-sm font-medium text-zinc-500">Event</dt>
                <dd class="mt-1 text-sm text-zinc-900"><%= @event.title %></dd>
              </div>
              <div>
                <dt class="text-sm font-medium text-zinc-500">Date</dt>
                <dd class="mt-1 text-sm text-zinc-900">
                  <%= if @event.start_date do %>
                    <%= Calendar.strftime(@event.start_date, "%B %d, %Y") %>
                  <% else %>
                    TBD
                  <% end %>
                </dd>
              </div>
              <div>
                <dt class="text-sm font-medium text-zinc-500">Time</dt>
                <dd class="mt-1 text-sm text-zinc-900">
                  <%= if @event.start_time do %>
                    <%= Calendar.strftime(@event.start_time, "%I:%M %p") %>
                  <% else %>
                    TBD
                  <% end %>
                </dd>
              </div>
            </div>
          </div>
        </div>
        <!-- Tickets Card -->
        <div class="bg-white rounded-lg shadow-sm border border-zinc-200 mb-6">
          <div class="px-6 py-4 border-b border-zinc-200">
            <h2 class="text-lg font-semibold text-zinc-900">Your Tickets</h2>
          </div>
          <div class="px-6 py-4">
            <div class="space-y-4">
              <%= for ticket <- @ticket_order.tickets do %>
                <div class="flex justify-between items-center p-4 bg-zinc-50 rounded-lg">
                  <div>
                    <p class="font-medium text-zinc-900"><%= ticket.ticket_tier.name %></p>
                    <p class="text-sm text-zinc-500">Ticket #<%= ticket.reference_id %></p>
                  </div>
                  <div class="text-right">
                    <p class="font-semibold text-zinc-900">
                      <%= cond do %>
                        <% ticket.ticket_tier.type == "donation" || ticket.ticket_tier.type == :donation -> %>
                          Donation
                        <% ticket.ticket_tier.price == nil -> %>
                          Free
                        <% Money.zero?(ticket.ticket_tier.price) -> %>
                          Free
                        <% true -> %>
                          <%= case Money.to_string(ticket.ticket_tier.price) do
                            {:ok, amount} -> amount
                            {:error, _} -> "Error"
                          end %>
                      <% end %>
                    </p>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
        <!-- Payment Summary Card -->
        <div class="bg-white rounded-lg shadow-sm border border-zinc-200 mb-6">
          <div class="px-6 py-4 border-b border-zinc-200">
            <h2 class="text-lg font-semibold text-zinc-900">Payment Summary</h2>
          </div>
          <div class="px-6 py-4">
            <div class="space-y-3">
              <div class="flex justify-between">
                <span class="text-zinc-600">Subtotal</span>
                <span class="font-medium">
                  <%= case Money.to_string(@ticket_order.total_amount) do
                    {:ok, amount} -> amount
                    {:error, _} -> "Error"
                  end %>
                </span>
              </div>
              <div class="flex justify-between">
                <span class="text-zinc-600">Payment Method</span>
                <span class="font-medium">
                  <%= if @ticket_order.payment do
                    get_payment_method_description(@ticket_order.payment)
                  else
                    "Free"
                  end %>
                </span>
              </div>
              <div class="border-t pt-3">
                <div class="flex justify-between">
                  <span class="text-lg font-semibold text-zinc-900">Total</span>
                  <span class="text-lg font-bold text-zinc-900">
                    <%= case Money.to_string(@ticket_order.total_amount) do
                      {:ok, amount} -> amount
                      {:error, _} -> "Error"
                    end %>
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
        <!-- Action Buttons -->
        <div class="flex flex-col sm:flex-row gap-4">
          <.button phx-click="view-tickets" class="flex-1 bg-blue-600 hover:bg-blue-700 text-white">
            View All My Tickets
          </.button>
          <.button phx-click="view-event" class="flex-1 bg-zinc-200 text-zinc-800 hover:bg-zinc-300">
            Back to Event
          </.button>
        </div>
        <!-- Additional Info -->
        <div class="mt-8 text-center">
          <p class="text-sm text-zinc-500">
            Need help? Contact us at
            <a href="mailto:info@ysc.org" class="text-blue-600 hover:text-blue-500">
              info@ysc.org
            </a>
          </p>
        </div>
      </div>
    </div>
    """
  end

  # Helper function to get payment method description
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
end
