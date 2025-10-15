defmodule YscWeb.AdminEventsLive.TicketTierForm do
  use YscWeb, :live_component

  alias Ysc.Events.TicketTier

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"#{@event_id}-ticket-tier-form"}>
      <.form
        :let={_f}
        for={@form}
        as={nil}
        id={@id}
        phx-submit="save"
        phx-target={@myself}
        phx-value-event_id={@event_id}
        phx-change="validate"
        class="space-y-4"
      >
        <.input type="hidden" value={@event_id} field={@form[:event_id]} />
        <.input type="text" label="Name" field={@form[:name]} required />

        <.input type="textarea" label="Description" field={@form[:description]} />

        <.input
          type="select"
          label="Type"
          field={@form[:type]}
          options={[
            {"Free", "free"},
            {"Paid", "paid"},
            {"Donation", "donation"}
          ]}
          required
        />

        <.input
          :if={@form[:type].value != "free"}
          type="text"
          label="Price"
          field={@form[:price]}
          placeholder="0.00"
          phx-hook="MoneyInput"
          value={format_money(@form[:price].value)}
          required
        >
          <div class="text-zinc-800">
            $
          </div>
        </.input>
        <.input
          type="checkbox"
          label="Unlimited quantity"
          field={@form[:unlimited_quantity]}
          phx-change="toggle_quantity_limit"
          phx-target={@myself}
        />

        <.input
          :if={!@form[:unlimited_quantity].value}
          type="number"
          label="Quantity"
          field={@form[:quantity]}
        />

        <.date_picker
          id="sales_start"
          label="Sale Starts"
          form={@form}
          start_date_field={@form[:start_date]}
          min={Date.utc_today()}
          required={true}
        />
        <.date_picker
          id="sale_ends"
          label="Sale Ends"
          form={@form}
          start_date_field={@form[:end_date]}
          min={sale_end_min_date(@form[:start_date].value)}
          required={true}
        />

        <.input type="checkbox" label="Requires Registration" field={@form[:requires_registration]} />

        <div class="flex justify-end">
          <.button type="submit">
            <%= if assigns[:ticket_tier] do %>
              <.icon name="hero-pencil" class="me-1 -mt-0.5" /> Update Ticket Tier
            <% else %>
              <.icon name="hero-plus" class="me-1 -mt-0.5" /> Add Ticket Tier
            <% end %>
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    changeset =
      if assigns[:ticket_tier] do
        # Editing existing ticket tier
        ticket_tier = assigns.ticket_tier

        attrs = %{
          unlimited_quantity: is_nil(ticket_tier.quantity) or ticket_tier.quantity == 0
        }

        TicketTier.changeset(ticket_tier, attrs)
      else
        # Creating new ticket tier
        TicketTier.changeset(%TicketTier{}, %{unlimited_quantity: false})
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("toggle_quantity_limit", %{"ticket_tier" => params}, socket) do
    params =
      params
      |> maybe_parse_price()
      |> maybe_set_free_price()
      |> maybe_set_unlimited_quantity()

    changeset =
      if socket.assigns[:ticket_tier] do
        TicketTier.changeset(socket.assigns.ticket_tier, params)
      else
        TicketTier.changeset(%TicketTier{}, params)
      end
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"ticket_tier" => params}, socket) do
    params =
      params
      |> maybe_parse_price()
      |> maybe_set_free_price()
      |> maybe_set_unlimited_quantity()

    changeset =
      if socket.assigns[:ticket_tier] do
        TicketTier.changeset(socket.assigns.ticket_tier, params)
      else
        TicketTier.changeset(%TicketTier{}, params)
      end
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign_form(changeset)}
  end

  @impl true
  def handle_event("save", %{"ticket_tier" => params}, socket) do
    params =
      params
      |> maybe_parse_price()
      |> maybe_set_free_price()
      |> maybe_set_unlimited_quantity()
      |> Map.put("event_id", socket.assigns.event_id)

    result =
      if socket.assigns[:ticket_tier] do
        # Updating existing ticket tier
        Ysc.Events.update_ticket_tier(socket.assigns.ticket_tier, params)
      else
        # Creating new ticket tier
        Ysc.Events.create_ticket_tier(params)
      end

    case result do
      {:ok, _ticket_tier} ->
        # Reset the form and close modal
        changeset = TicketTier.changeset(%TicketTier{}, %{unlimited_quantity: false})
        action = if socket.assigns[:ticket_tier], do: "updated", else: "added"

        {:noreply,
         socket
         |> put_flash(:info, "Ticket tier #{action} successfully")
         |> assign_form(changeset)
         |> push_navigate(to: ~p"/admin/events/#{socket.assigns.event_id}/tickets")}

      {:error, changeset} ->
        {:noreply, socket |> assign_form(changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "ticket_tier")

    # Only show errors if the changeset has been validated (has an action)
    check_errors = changeset.action == :validate
    assign(socket, form: form, check_errors: check_errors)
  end

  defp format_money(nil), do: nil
  defp format_money(""), do: nil

  defp format_money(%Money{} = value) do
    case Ysc.MoneyHelper.format_money(value) do
      {:ok, money} -> money
      _ -> nil
    end
  end

  defp sale_end_min_date(nil), do: Date.utc_today()
  defp sale_end_min_date(""), do: Date.utc_today()

  defp sale_end_min_date(start) do
    start
  end

  defp maybe_parse_price(params) do
    case params["price"] do
      nil -> params
      "" -> params
      price -> Map.put(params, "price", Ysc.MoneyHelper.parse_money(price))
    end
  end

  defp maybe_set_free_price(params) do
    if params["type"] == "free" do
      Map.put(params, "price", Money.new(0, :USD))
    else
      params
    end
  end

  defp maybe_set_unlimited_quantity(params) do
    case params["unlimited_quantity"] do
      "true" -> Map.put(params, "quantity", nil)
      true -> Map.put(params, "quantity", nil)
      _ -> params
    end
  end
end
