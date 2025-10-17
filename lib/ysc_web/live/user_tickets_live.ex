defmodule YscWeb.UserTicketsLive do
  use YscWeb, :live_view

  alias Ysc.Tickets

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10">
      <div class="max-w-screen-lg mx-auto px-4">
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-zinc-900">My Tickets</h1>
          <p class="text-zinc-600 mt-2">View and manage your event tickets</p>
        </div>

        <div class="space-y-6">
          <%= if Enum.empty?(@ticket_orders) do %>
            <div class="text-center py-12">
              <div class="text-zinc-400 mb-4">
                <.icon name="hero-ticket" class="w-16 h-16 mx-auto" />
              </div>
              <h3 class="text-lg font-medium text-zinc-900 mb-2">No tickets yet</h3>
              <p class="text-zinc-600 mb-6">You haven't purchased any event tickets yet.</p>
              <.link
                href={~p"/events"}
                class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
              >
                Browse Events
              </.link>
            </div>
          <% else %>
            <%= for ticket_order <- @ticket_orders do %>
              <div class="bg-white border border-zinc-200 rounded-lg shadow-sm">
                <div class="p-6">
                  <div class="flex items-start justify-between">
                    <div class="flex-1">
                      <div class="flex items-center space-x-3">
                        <h3 class="text-lg font-semibold text-zinc-900">
                          <%= ticket_order.event.title %>
                        </h3>
                        <.status_badge status={ticket_order.status} />
                      </div>

                      <p class="text-sm text-zinc-600 mt-1">
                        Order #<%= ticket_order.reference_id %> • <%= format_date(
                          ticket_order.inserted_at
                        ) %>
                      </p>

                      <div class="mt-3">
                        <p class="text-sm text-zinc-600">
                          <span class="font-medium">Total:</span>
                          <%= format_price(ticket_order.total_amount) %>
                        </p>

                        <p class="text-sm text-zinc-600">
                          <span class="font-medium">Tickets:</span>
                          <%= length(ticket_order.tickets) %> ticket(s)
                        </p>
                      </div>
                    </div>

                    <div class="flex flex-col items-end space-y-2">
                      <%= if ticket_order.status == :pending do %>
                        <div class="text-sm text-amber-600">
                          <.icon name="hero-clock" class="w-4 h-4 inline me-1" />
                          Expires <%= format_time_remaining(ticket_order.expires_at) %>
                        </div>
                        <.button
                          color="red"
                          phx-click="cancel-order"
                          phx-value-order-id={ticket_order.id}
                        >
                          Cancel Order
                        </.button>
                      <% end %>

                      <%= if ticket_order.status == :completed do %>
                        <.button phx-click="view-tickets" phx-value-order-id={ticket_order.id}>
                          View Tickets
                        </.button>
                      <% end %>
                    </div>
                  </div>
                  <!-- Ticket Details -->
                  <%= if ticket_order.status == :completed do %>
                    <div class="mt-4 pt-4 border-t border-zinc-200">
                      <h4 class="text-sm font-medium text-zinc-900 mb-3">Ticket Details</h4>
                      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                        <%= for ticket <- ticket_order.tickets do %>
                          <div class="bg-zinc-50 rounded-md p-3">
                            <div class="flex items-center justify-between">
                              <div>
                                <p class="text-sm font-medium text-zinc-900">
                                  <%= ticket.ticket_tier.name %>
                                </p>
                                <p class="text-xs text-zinc-600">
                                  Ticket #<%= ticket.reference_id %>
                                </p>
                              </div>
                              <div class="text-right">
                                <p class="text-sm font-medium text-zinc-900">
                                  <%= case ticket.ticket_tier.type do %>
                                    <% :free -> %>
                                      Free
                                    <% _ -> %>
                                      <%= format_price(ticket.ticket_tier.price) %>
                                  <% end %>
                                </p>
                                <.status_badge status={ticket.status} size="sm" />
                              </div>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to ticket order updates
      # Phoenix.PubSub.subscribe(Ysc.PubSub, "ticket_orders:#{socket.assigns.current_user.id}")
    end

    ticket_orders = Tickets.list_user_ticket_orders(socket.assigns.current_user.id)

    {:ok,
     socket
     |> assign(:page_title, "My Tickets")
     |> assign(:ticket_orders, ticket_orders)}
  end

  @impl true
  def handle_event("cancel-order", %{"order-id" => order_id}, socket) do
    case Tickets.get_ticket_order(order_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Order not found")}

      ticket_order ->
        case Tickets.cancel_ticket_order(ticket_order, "User cancelled") do
          {:ok, _cancelled_order} ->
            # Refresh the ticket orders list
            ticket_orders = Tickets.list_user_ticket_orders(socket.assigns.current_user.id)

            {:noreply,
             socket
             |> assign(:ticket_orders, ticket_orders)
             |> put_flash(:info, "Order cancelled successfully")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to cancel order: #{reason}")}
        end
    end
  end

  @impl true
  def handle_event("view-tickets", %{"order-id" => order_id}, socket) do
    # Redirect to a detailed ticket view page
    {:noreply, redirect(socket, to: ~p"/tickets/#{order_id}")}
  end

  ## Helper Functions

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
      case @status do
        :pending -> "bg-amber-100 text-amber-800"
        :completed -> "bg-green-100 text-green-800"
        :cancelled -> "bg-red-100 text-red-800"
        :expired -> "bg-zinc-100 text-zinc-800"
        _ -> "bg-zinc-100 text-zinc-800"
      end
    ]}>
      <%= String.capitalize(to_string(@status)) %>
    </span>
    """
  end

  defp format_date(datetime) do
    Timex.format!(datetime, "{Mshort} {D}, {YYYY}")
  end

  defp format_price(%Money{} = money) do
    Ysc.MoneyHelper.format_money!(money)
  end

  defp format_price(_), do: "$0.00"

  defp format_time_remaining(expires_at) do
    now = DateTime.utc_now()

    if DateTime.compare(now, expires_at) == :gt do
      "Expired"
    else
      diff_seconds = DateTime.diff(expires_at, now)

      cond do
        diff_seconds < 60 ->
          "in #{diff_seconds} seconds"

        diff_seconds < 3600 ->
          minutes = div(diff_seconds, 60)
          "in #{minutes} minute#{if minutes == 1, do: "", else: "s"}"

        true ->
          hours = div(diff_seconds, 3600)
          "in #{hours} hour#{if hours == 1, do: "", else: "s"}"
      end
    end
  end
end
