defmodule YscWeb.AdminEventsLive.TicketTierForm do
  use YscWeb, :live_component

  alias Ysc.Events
  alias Ysc.Events.TicketTier

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"#{@event_id}-ticket-tier-form"}>
      <.form
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
        <.input type="text" label="Description" field={@form[:description]} required />

        <.input type="number" label="Price" field={@form[:price]} required />
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
          min={Date.utc_today()}
          required={true}
        />

        <%!-- <.input type="select" label="Requires Registration" field={@form[:requires_registration]} /> --%>

        <div class="flex justify-end">
          <.button type="submit">Add Ticket Tier</.button>
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
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"event" => event_params}, socket) do
    # agenda = Agendas.get_agenda!(socket.assigns.agenda_id)
    # Agendas.update_agenda(socket.assigns.event_id, agenda, agenda_params)
    Events.schedule_event(socket.assigns.event, event_params["publish_at"])

    {:noreply,
     socket
     |> put_flash(:info, "Event scheduled successfully")
     |> push_navigate(to: ~p"/admin/events/#{socket.assigns.event.id}/edit")}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
