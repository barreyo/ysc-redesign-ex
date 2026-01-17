defmodule YscWeb.AdminEventsLive.TicketTierManagement do
  use YscWeb, :live_component

  alias Ysc.Events

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Ticket Tiers List -->
      <div class="border border-zinc-200 rounded p-4 sm:p-6">
        <div class="flex flex-col sm:flex-row sm:justify-between sm:items-center gap-3 sm:gap-0 mb-4">
          <h3 class="text-lg font-semibold">Ticket Tiers</h3>
          <div class="flex items-center">
            <.button
              phx-click="open-add-ticket-tier-modal"
              phx-target={@myself}
              class="w-full sm:w-auto"
            >
              <.icon name="hero-plus" class="w-4 h-4 me-1" /> Add Ticket Tier
            </.button>
          </div>
        </div>

        <div :if={length(@ticket_tiers) == 0} class="text-center py-8 text-zinc-500">
          <p class="font-semibold">No ticket tiers created yet.</p>
          <p class="text-sm">Click "Add Ticket Tier" to create your first ticket tier.</p>
        </div>

        <div :if={length(@ticket_tiers) > 0} class="space-y-3 sm:space-y-4">
          <%= for ticket_tier <- @ticket_tiers do %>
            <div class="border border-zinc-200 rounded p-3 sm:p-4 hover:bg-zinc-50 transition-colors">
              <div class="flex flex-col sm:flex-row sm:justify-between sm:items-start gap-3 sm:gap-0">
                <div class="flex-1">
                  <div class="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-3 mb-2">
                    <h4 class="font-semibold text-lg"><%= ticket_tier.name %></h4>
                    <.badge type={ticket_tier_type_to_badge_style(ticket_tier.type)}>
                      <%= String.capitalize(to_string(ticket_tier.type)) %>
                    </.badge>
                  </div>

                  <p :if={ticket_tier.description} class="text-zinc-600 text-sm mb-2">
                    <%= ticket_tier.description %>
                  </p>

                  <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4 text-sm">
                    <div>
                      <span class="font-medium text-zinc-700">Price:</span>
                      <span class="ml-1">
                        <%= case ticket_tier.type do %>
                          <% "free" -> %>
                            Free
                          <% "donation" -> %>
                            User sets amount
                          <% :donation -> %>
                            User sets amount
                          <% _ -> %>
                            <%= format_money_safe(ticket_tier.price) %>
                        <% end %>
                      </span>
                    </div>

                    <div>
                      <span class="font-medium text-zinc-700">Quantity:</span>
                      <span class="ml-1">
                        <%= case ticket_tier.quantity do %>
                          <% nil -> %>
                            Unlimited (<%= ticket_tier.sold_tickets_count %> sold)
                          <% 0 -> %>
                            Unlimited (<%= ticket_tier.sold_tickets_count %> sold)
                          <% quantity -> %>
                            <%= "#{ticket_tier.sold_tickets_count}/#{quantity}" %>
                        <% end %>
                      </span>
                    </div>

                    <div>
                      <span class="font-medium text-zinc-700">Sales Period:</span>
                      <span class="ml-1">
                        <%= format_sales_period(ticket_tier.start_date, ticket_tier.end_date) %>
                      </span>
                    </div>

                    <div>
                      <span class="font-medium text-zinc-700">Registration:</span>
                      <span class="ml-1">
                        <%= if ticket_tier.requires_registration, do: "Required", else: "Not Required" %>
                      </span>
                    </div>
                  </div>
                </div>

                <div class="flex flex-row sm:flex-col gap-2 sm:gap-1 sm:ml-4">
                  <.button
                    color="blue"
                    phx-click="edit-ticket-tier"
                    phx-value-id={ticket_tier.id}
                    phx-target={@myself}
                    phx-disable-with="Loading..."
                    class="flex-1 sm:flex-none"
                  >
                    <.icon name="hero-pencil" class="w-4 h-4 sm:me-0" />
                    <span class="sm:hidden ml-1">Edit</span>
                  </.button>

                  <.button
                    color="red"
                    phx-click="delete-ticket-tier"
                    phx-value-id={ticket_tier.id}
                    phx-target={@myself}
                    phx-disable-with="Deleting..."
                    data-confirm="Are you sure you want to delete this ticket tier? This action cannot be undone."
                    disabled={ticket_tier.sold_tickets_count > 0}
                    title={
                      if ticket_tier.sold_tickets_count > 0,
                        do: "Cannot delete ticket tier with sold tickets",
                        else: "Delete ticket tier"
                    }
                    class="flex-1 sm:flex-none"
                  >
                    <.icon name="hero-trash" class="w-4 h-4 sm:me-0" />
                    <span class="sm:hidden ml-1">Delete</span>
                  </.button>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      <!-- Ticket Purchases Summary -->
      <div class="border border-zinc-200 rounded p-4 sm:p-6">
        <div class="flex flex-col sm:flex-row sm:justify-between sm:items-center gap-2 sm:gap-0 mb-4">
          <h3 class="text-lg font-semibold">Ticket Purchases</h3>
          <div class="flex items-center gap-3">
            <span class="text-sm text-zinc-600">
              <%= length(@ticket_purchases) %> purchase<%= if length(@ticket_purchases) != 1, do: "s" %>
            </span>
            <.button
              phx-click="export-tickets-csv"
              phx-target={@myself}
              phx-disable-with="Exporting..."
              color="blue"
              class="w-full sm:w-auto"
            >
              <.icon name="hero-arrow-down-tray" class="w-4 h-4 me-1" /> Export CSV
            </.button>
          </div>
        </div>

        <div :if={length(@ticket_purchases) == 0} class="text-center py-8 text-zinc-500">
          <p class="font-semibold">No tickets purchased yet.</p>
          <p class="text-sm">Ticket purchases will appear here once users start buying tickets.</p>
        </div>

        <div :if={length(@ticket_purchases) > 0} class="space-y-3 sm:space-y-4">
          <%= for purchase <- @ticket_purchases do %>
            <div class="border border-zinc-200 rounded p-3 sm:p-4">
              <div class="flex flex-col sm:flex-row sm:justify-between sm:items-start gap-3 sm:gap-0">
                <div class="flex-1">
                  <div class="flex flex-col sm:flex-row sm:items-center gap-1 sm:gap-3 mb-2">
                    <h4 class="font-semibold"><%= purchase.user_name %></h4>
                    <span class="text-sm text-zinc-600"><%= purchase.user_email %></span>
                  </div>

                  <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 sm:gap-4 text-sm">
                    <div>
                      <span class="font-medium text-zinc-700">Ticket Tier:</span>
                      <span class="ml-1"><%= purchase.ticket_tier_name %></span>
                    </div>

                    <div>
                      <span class="font-medium text-zinc-700">Quantity:</span>
                      <span class="ml-1"><%= purchase.ticket_count %></span>
                    </div>

                    <div>
                      <span class="font-medium text-zinc-700">Total:</span>
                      <span class="ml-1">
                        <%= case purchase.total_amount do %>
                          <% %Money{amount: 0} -> %>
                            Free
                          <% amount -> %>
                            <%= format_money_safe(amount) %>
                        <% end %>
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      <!-- Add Ticket Tier Modal -->
      <.modal
        :if={@show_add_modal}
        id="add-ticket-tier-modal"
        show
        on_cancel={JS.push("close-add-ticket-tier-modal", target: @myself)}
      >
        <.live_component
          id={"ticket-tier-form-#{@event_id}"}
          module={YscWeb.AdminEventsLive.TicketTierForm}
          event_id={@event_id}
        />
      </.modal>
      <!-- Edit Ticket Tier Modal -->
      <.modal
        :if={@show_edit_modal}
        id="edit-ticket-tier-modal"
        show
        on_cancel={JS.push("close-edit-ticket-tier-modal", target: @myself)}
      >
        <.live_component
          :if={@editing_ticket_tier}
          id={"edit-ticket-tier-form-#{@editing_ticket_tier.id}"}
          module={YscWeb.AdminEventsLive.TicketTierForm}
          event_id={@event_id}
          ticket_tier={@editing_ticket_tier}
        />
      </.modal>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    ticket_tiers = Events.list_ticket_tiers_for_event(assigns.event_id)
    ticket_purchases = Events.get_ticket_purchase_summary(assigns.event_id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:ticket_tiers, ticket_tiers)
     |> assign(:ticket_purchases, ticket_purchases)
     |> assign(:show_add_modal, false)
     |> assign(:show_edit_modal, false)
     |> assign(:editing_ticket_tier, nil)}
  end

  @impl true
  def handle_event("open-add-ticket-tier-modal", _params, socket) do
    {:noreply, assign(socket, :show_add_modal, true)}
  end

  @impl true
  def handle_event("close-add-ticket-tier-modal", _params, socket) do
    {:noreply, assign(socket, :show_add_modal, false)}
  end

  @impl true
  def handle_event("close-edit-ticket-tier-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_edit_modal, false)
     |> assign(:editing_ticket_tier, nil)}
  end

  @impl true
  def handle_event("close-modal", _params, socket) do
    # Refresh the ticket tier list when modal closes (in case a new tier was added or updated)
    ticket_tiers = Events.list_ticket_tiers_for_event(socket.assigns.event_id)

    {:noreply,
     socket
     |> assign(:show_add_modal, false)
     |> assign(:show_edit_modal, false)
     |> assign(:editing_ticket_tier, nil)
     |> assign(:ticket_tiers, ticket_tiers)}
  end

  @impl true
  def handle_event("edit-ticket-tier", %{"id" => id}, socket) do
    ticket_tier = Events.get_ticket_tier!(id)

    {:noreply,
     socket
     |> assign(:show_edit_modal, true)
     |> assign(:editing_ticket_tier, ticket_tier)}
  end

  @impl true
  def handle_event("delete-ticket-tier", %{"id" => id}, socket) do
    ticket_tier = Events.get_ticket_tier!(id)

    # Check if any tickets have been sold for this tier
    sold_count = Events.count_tickets_for_tier(id)

    if sold_count > 0 do
      {:noreply, put_flash(socket, :error, "Cannot delete ticket tier with sold tickets")}
    else
      case Events.delete_ticket_tier(ticket_tier) do
        {:ok, _ticket_tier} ->
          ticket_tiers = Events.list_ticket_tiers_for_event(socket.assigns.event_id)

          {:noreply,
           socket
           |> put_flash(:info, "Ticket tier deleted successfully")
           |> assign(:ticket_tiers, ticket_tiers)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to delete ticket tier")}
      end
    end
  end

  @impl true
  def handle_event("export-tickets-csv", _params, socket) do
    tickets = Events.list_tickets_for_export(socket.assigns.event_id)

    csv_content =
      tickets
      |> build_csv_rows()
      |> CSV.encode(headers: true)
      |> Enum.to_list()
      |> IO.iodata_to_binary()

    filename = "tickets_export_#{DateTime.utc_now() |> DateTime.to_unix()}.csv"

    # Base64 encode the content for download
    encoded_content = Base.encode64(csv_content)

    {:noreply,
     socket
     |> push_event("download-csv", %{content: encoded_content, filename: filename})}
  end

  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.TicketTierAdded{ticket_tier: ticket_tier}},
        socket
      ) do
    if ticket_tier.event_id == socket.assigns.event_id do
      ticket_tiers = Events.list_ticket_tiers_for_event(socket.assigns.event_id)
      {:noreply, assign(socket, :ticket_tiers, ticket_tiers)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.TicketTierUpdated{ticket_tier: ticket_tier}},
        socket
      ) do
    if ticket_tier.event_id == socket.assigns.event_id do
      ticket_tiers = Events.list_ticket_tiers_for_event(socket.assigns.event_id)
      {:noreply, assign(socket, :ticket_tiers, ticket_tiers)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.TicketTierDeleted{ticket_tier: ticket_tier}},
        socket
      ) do
    if ticket_tier.event_id == socket.assigns.event_id do
      ticket_tiers = Events.list_ticket_tiers_for_event(socket.assigns.event_id)
      {:noreply, assign(socket, :ticket_tiers, ticket_tiers)}
    else
      {:noreply, socket}
    end
  end

  defp build_csv_rows(tickets) do
    Enum.map(tickets, fn ticket ->
      # Purchaser information (user who bought the ticket)
      purchaser_first_name = ticket.user.first_name || ""
      purchaser_last_name = ticket.user.last_name || ""
      purchaser_email = ticket.user.email || ""
      phone = ticket.user.phone_number || ""

      # Attendee information (from ticket_detail if registration was required)
      {attendee_first_name, attendee_last_name, attendee_email} =
        if ticket.ticket_tier && ticket.ticket_tier.requires_registration &&
             ticket.ticket_detail do
          {
            ticket.ticket_detail.first_name || "",
            ticket.ticket_detail.last_name || "",
            ticket.ticket_detail.email || ""
          }
        else
          # If no registration required, attendee is the same as purchaser
          {purchaser_first_name, purchaser_last_name, purchaser_email}
        end

      # Build CSV row with both purchaser and attendee information
      base_row = %{
        "Ticket Reference" => ticket.reference_id || "",
        "Ticket Tier" => (ticket.ticket_tier && ticket.ticket_tier.name) || "",
        "Purchaser First Name" => purchaser_first_name,
        "Purchaser Last Name" => purchaser_last_name,
        "Purchaser Email" => purchaser_email,
        "Purchaser Phone" => phone,
        "Attendee First Name" => attendee_first_name,
        "Attendee Last Name" => attendee_last_name,
        "Attendee Email" => attendee_email
      }

      # If ticket details exist, add a note that registration was provided
      if ticket.ticket_detail do
        Map.put(base_row, "Registration Provided", "Yes")
      else
        Map.put(base_row, "Registration Provided", "No")
      end
    end)
  end

  defp ticket_tier_type_to_badge_style(type) when is_atom(type) do
    ticket_tier_type_to_badge_style(to_string(type))
  end

  defp ticket_tier_type_to_badge_style("free"), do: "green"
  defp ticket_tier_type_to_badge_style("paid"), do: "sky"
  defp ticket_tier_type_to_badge_style("donation"), do: "yellow"
  defp ticket_tier_type_to_badge_style(_), do: "default"

  defp format_sales_period(nil, nil), do: "Always available"
  defp format_sales_period(start_date, nil), do: "From #{format_date(start_date)}"
  defp format_sales_period(nil, end_date), do: "Until #{format_date(end_date)}"

  defp format_sales_period(start_date, end_date),
    do: "#{format_date(start_date)} - #{format_date(end_date)}"

  defp format_date(nil), do: ""

  defp format_date(date) when is_binary(date) do
    case Timex.parse(date, "{ISO:Extended}") do
      {:ok, parsed_date} -> Timex.format!(parsed_date, "{Mshort} {D}, {YYYY}")
      {:error, _} -> date
    end
  end

  defp format_date(date), do: Timex.format!(date, "{Mshort} {D}, {YYYY}")

  defp format_money_safe(nil), do: "—"
  defp format_money_safe(""), do: "—"

  defp format_money_safe(%Money{} = money) do
    case Ysc.MoneyHelper.format_money(money) do
      formatted when is_binary(formatted) and formatted != "" -> formatted
      {:ok, formatted} when is_binary(formatted) -> formatted
      {:error, _} -> "Invalid amount"
      _ -> "—"
    end
  end

  defp format_money_safe(_), do: "—"
end
