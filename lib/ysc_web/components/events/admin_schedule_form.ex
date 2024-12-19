defmodule YscWeb.AdminEventsLive.ScheduleEventForm do
  use YscWeb, :live_component

  alias Ysc.Events
  alias Ysc.Events.Event

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"schedule-drop-#{@event_id}"}>
      <.form
        for={@form}
        as={nil}
        id={"schedule_form-#{@event_id}"}
        phx-submit="save"
        phx-target={@myself}
        phx-value-event_id={@event.id}
        class="space-y-4"
      >
        <.input
          type="datetime-local"
          field={@form[:publish_at]}
          label="Scheduled At"
          phx-mounted={JS.focus()}
        />

        <div class="flex justify-end">
          <.button type="submit">Set Schedule</.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{event: event} = assigns, socket) do
    changeset = Event.changeset(event, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"event" => _event_params}, socket) do
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
