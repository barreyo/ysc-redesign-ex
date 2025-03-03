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

        <.input
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
        <.input type="number" label="Quantity" field={@form[:quantity]} />

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
            <.icon name="hero-plus" class="me-1 -mt-0.5" /> Add Ticket Tier
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    changeset = TicketTier.changeset(%TicketTier{}, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"ticket_tier" => _params} = event_params, socket) do
    params = update_in(event_params["price"], &Ysc.MoneyHelper.parse_money/1)

    changeset =
      TicketTier.changeset(%TicketTier{}, params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign_form(changeset)}
  end

  @impl true
  def handle_event("save", %{"ticket_tier" => _params}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Ticket tier added")
     |> push_navigate(to: ~p"/admin/events/#{socket.assigns.event_id}/tickets")}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "ticket_tier")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
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
end
