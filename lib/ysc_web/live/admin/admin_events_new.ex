defmodule YscWeb.AdminEventsNewLive do
  use YscWeb, :live_view

  alias HtmlSanitizeEx.Scrubber

  alias Ysc.Events.Event
  alias Ysc.Events

  alias Ysc.Events.Agenda
  alias Ysc.Events.AgendaItem
  alias Ysc.Agendas

  @save_debounce_timeout 2000
  @s3_bucket "media"

  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      email={@current_user.email}
      first_name={@current_user.first_name}
      last_name={@current_user.last_name}
      user_id={@current_user.id}
      most_connected_country={@current_user.most_connected_country}
    >
      <div class="flex py-6 flex-col">
        <div class="flex flex-row justify-between">
          <div class="flex flex-col space-y-1">
            <div class="flex flex-row items-center space-x-3">
              <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
                <%= @event_title %>
              </h1>

              <div>
                <.badge type={event_state_to_badge_style(@state)}>
                  <%= String.capitalize("#{@state}") %>
                </.badge>
              </div>
            </div>

            <div
              :if={@start_date != nil && @start_date != ""}
              class="flex flex-row space-x-1 items-center"
            >
              <.icon name="hero-calendar-days" class="text-zinc-600" />
              <p class="text-sm text-zinc-600">
                <%= Ysc.Events.DateTimeFormatter.format_datetime(%{
                  start_date: format_date(@start_date),
                  start_time: format_time(@start_time),
                  end_date: format_date(@end_date),
                  end_time: format_time(@end_time)
                }) %>
              </p>
            </div>
          </div>

          <div class="pl-4 space-x-1 flex flex-row">
            <div :if={@event.state in [:draft, :scheduled]}>
              <.button color="blue" phx-click="publish-event">
                <.icon name="hero-document-arrow-up" class="w-5 h-5 -mt-1 me-1" />Publish
              </.button>
            </div>

            <div :if={@event.state in [:published]}>
              <.button color="gray" phx-click="unpublish-event">
                <.icon name="hero-document-arrow-down" class="w-5 h-5 -mt-1 me-1" />Unpublish
              </.button>
            </div>

            <.dropdown
              :if={@event.state in [:draft, :scheduled]}
              id="edit-post-more"
              right={true}
              class={
                Enum.join(
                  [
                    "text-zinc-100 px-3 leading-6 py-2 text-sm font-semibold transition duration-300",
                    @event.state == :scheduled && "bg-green-700 hover:bg-green-800",
                    @event.state != :scheduled && "bg-blue-700 hover:bg-blue-800"
                  ],
                  " "
                )
              }
            >
              <:button_block>
                <.icon name="hero-clock" class="w-5 h-5 me-1" /><%= schedule_button_text(@event.state) %>
                <.icon name="hero-chevron-down" class="ms-2" />
              </:button_block>

              <div class="w-full px-2 py-4">
                <.live_component
                  id={@event.id}
                  event={@event}
                  module={YscWeb.AdminEventsLive.ScheduleEventForm}
                  event_id={@event.id}
                />
              </div>
            </.dropdown>

            <.dropdown
              id="edit-event-more"
              right={true}
              class="text-zinc-800 hover:bg-zinc-100 hover:text-black"
            >
              <:button_block>
                <.icon name="hero-ellipsis-vertical" class="w-6 h-6" />
              </:button_block>

              <div class="w-full divide-y divide-zinc-100 text-sm text-zinc-700">
                <ul class="py-2 text-sm font-medium text-zinc-800 px-2">
                  <li
                    :if={@event.state == :published}
                    class="block py-2 px-3 transition ease-in-out duration-200 hover:bg-zinc-100"
                  >
                    <button type="button" class="w-full text-left px-1" phx-click="cancel-event">
                      <.icon name="hero-minus-circle" class="me-1 -mt-1 w-5 h-5" />Cancel Event
                    </button>
                  </li>

                  <li class="block py-2 px-3 transition text-red-600 ease-in-out duration-200 hover:bg-zinc-100">
                    <button type="button" class="w-full text-left px-1" phx-click="delete-event">
                      <.icon name="hero-trash" class="w-5 h-5 -mt-1" />
                      <span>Delete Event</span>
                    </button>
                  </li>
                </ul>
              </div>
            </.dropdown>
          </div>
        </div>

        <div class="pt-4">
          <div class="text-sm font-medium text-center text-zinc-500 border-b border-zinc-200">
            <ul class="flex flex-wrap -mb-px">
              <li class="me-2">
                <.link
                  navigate={~p"/admin/events/new"}
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :edit && "text-blue-600 border-blue-600 active",
                    @live_action != :edit &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Event Details
                </.link>
              </li>
              <li class="me-2">
                <.link
                  navigate={~p"/admin/events/new/tickets"}
                  class={[
                    "inline-block p-4 border-b-2 rounded-t-lg",
                    @live_action == :tickets && "text-blue-600 border-blue-600 active",
                    @live_action != :tickets &&
                      "hover:text-zinc-600 hover:border-zinc-300 border-transparent"
                  ]}
                >
                  Tickets (0/0)
                </.link>
              </li>
            </ul>
          </div>
        </div>

        <div :if={@live_action == :edit} class="relative py-8">
          <div class="border max-w-3xl rounded border-zinc-200 py-6 px-4 space-y-4">
            <h2 class="text-xl font-bold">Cover Image</h2>

            <.live_component
              id={"#{@event.id}-cover-image"}
              module={YscWeb.Components.ImageUploadComponent}
              event_id={@event.id}
            />
          </div>

          <.form
            for={@form}
            id="new_event_form"
            phx-submit="save"
            phx-change="validate"
            phx-trigger-action={@trigger_submit}
            method="post"
            class="space-y-6 max-w-3xl"
          >
            <.input type="hidden" field={@form[:organizer_id]} value={@current_user.id} />

            <div class="border rounded border-zinc-200 py-6 px-4 space-y-4">
              <div>
                <h2 class="text-xl font-bold">Basics</h2>
                <p class="text-zinc-600 text-sm">
                  Give your event a nice title and summary to attract attendees.
                </p>
              </div>
              <.input
                type="text"
                field={@form[:title]}
                label="Event Title*"
                phx-debounce="300"
                required
              />
              <.input
                type="text"
                field={@form[:description]}
                label={"Summary (#{@description_length}/200)*"}
                phx-debounce="300"
                required
              />
            </div>

            <div class="border border-zinc-200 rounded py-6 px-4 space-y-4">
              <h2 class="text-xl font-bold mb-2">Date and Location</h2>

              <h3 class="text-lg font-medium">Date and Time</h3>
              <div class="flex flex-row w-full space-x-4">
                <div class="flex">
                  <.date_range_picker
                    label="Date*"
                    id="event_date"
                    form={@form}
                    start_date_field={@form[:start_date]}
                    end_date_field={@form[:end_date]}
                    min={Date.utc_today()}
                  />
                </div>

                <.input
                  type="time"
                  id="start_time"
                  step="60"
                  field={@form[:start_time]}
                  label="Start Time*"
                />
                <.input type="time" id="end_time" step="60" field={@form[:end_time]} label="End Time" />
              </div>

              <h3 class="text-lg pt-4 font-medium">Location</h3>
              <div class="space-y-4">
                <.input
                  type="text"
                  field={@form[:location_name]}
                  label="Location Name"
                  phx-debounce="300"
                />
                <.input type="text" field={@form[:address]} label="Address" phx-debounce="300" />
                <div class="flex flex-row space-x-4">
                  <.input type="number" step="any" field={@form[:latitude]} label="Latitude" />
                  <.input type="number" step="any" field={@form[:longitude]} label="Longitude" />
                </div>
                <div class="space-y-2">
                  <.live_component
                    id={"#{@event.id}-map"}
                    module={YscWeb.Components.MapComponent}
                    event_id={@event.id}
                    latitude={@form[:latitude].value}
                    longitude={@form[:longitude].value}
                    locked={false}
                  />
                  <p class="text-zinc-700 text-sm">
                    Click on the map to set marker that will be displayed on event page.
                  </p>
                </div>
              </div>
            </div>

            <div class="border border-zinc-200 rounded py-6 px-4 space-y-4">
              <div>
                <h2 class="text-xl font-bold">Overview</h2>
                <p class="text-zinc-600 text-sm">
                  Add more details about the event to help attendees understand what to expect.
                </p>
              </div>

              <div class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-none">
                <.input
                  type="hidden"
                  id="post[raw_body]"
                  field={@form[:raw_details]}
                  post-id={@event.id}
                  phx-hook="TrixHook"
                  phx-debounce={200}
                />
                <div id="richtext" phx-update="ignore">
                  <trix-editor
                    input="post[raw_body]"
                    class="trix-content block px-4 py-2 bg-white border-zinc-200 focus:ring-1 focus:ring-blue-400 focus:border-blue-400 transition border-l border-b border-r focus:ring-0 text-wrap"
                    placeholder="Write something delightful and nice..."
                  >
                  </trix-editor>
                </div>
              </div>
            </div>
          </.form>

          <div class="max-w-3xl mt-6">
            <div class="border border-zinc-200 rounded py-6 px-4 space-y-4">
              <div>
                <h2 class="text-xl font-bold">Agenda</h2>
                <p class="text-zinc-600 text-sm">
                  Add schedules or itineraries to help attendees plan their day.
                </p>
              </div>

              <.button type="button" phx-click="add-agenda">
                <.icon name="hero-plus" class="-mt-0.5" /> Add Agenda
              </.button>

              <ul
                id="agendas"
                phx-update="stream"
                phx-hook="Sortable"
                class="w-full flex gap-3 snap-x overflow-x-auto"
              >
                <li
                  :for={{id, agenda} <- @streams.agendas}
                  id={id}
                  data-id={agenda.id}
                  class="py-4 bg-zinc-100 rounded-lg flex-shrink-0"
                >
                  <div class="mx-auto max-w-7xl px-4 space-y-4">
                    <div class="flex flex-row justify-between space-x-4">
                      <div class="w-full">
                        <.live_component
                          id={"edit-agenda-title-#{agenda.id}"}
                          module={YscWeb.AgendasLive.FormComponent}
                          agenda_id={agenda.id}
                          event_id={@event.id}
                          agenda={agenda}
                        />
                      </div>

                      <.link phx-click="delete-agenda" phx-value-id={agenda.id} alt="delete agenda">
                        <.icon
                          name="hero-trash"
                          class="px-2 py-2 hover:bg-red-600 rounded transition duration-200"
                        />
                      </.link>
                    </div>

                    <.live_component
                      id={agenda.id}
                      module={YscWeb.AgendaEditComponent}
                      agenda={agenda}
                      event_id={@event.id}
                    />
                  </div>
                </li>
              </ul>
            </div>
          </div>
        </div>

        <div :if={@live_action == :tickets}>
          <p>tickets</p>
        </div>
      </div>
    </.side_menu>
    """
  end

  def mount(%{"id" => id} = _params, _session, socket) do
    if connected?(socket) do
      Agendas.subscribe(id)
    end

    event = Events.get_event!(id)
    event_changeset = Event.changeset(event, %{})
    agendas = Agendas.list_agendas_for_event(event.id)

    {:ok,
     socket
     |> assign(:event, event)
     |> assign(:active_page, :events)
     |> assign(:page_title, event.title)
     |> assign(:description_length, description_length(event.description))
     |> assign(:event_title, event.title)
     |> assign(:state, event.state)
     |> assign(:start_date, event.start_date)
     |> assign(:end_date, event.end_date)
     |> assign(:start_time, event.start_time)
     |> assign(:end_time, event.end_time)
     |> assign(trigger_submit: false, check_errors: false)
     |> stream(:agendas, agendas)
     |> assign(form: to_form(event_changeset, as: "event"))}
  end

  def mount(params, _session, socket) do
    {:ok, inserted_event} =
      Events.create_event(%{
        title: "New Event",
        description: "",
        state: :draft,
        organizer_id: socket.assigns.current_user.id
      })

    {:ok, push_navigate(socket, to: "/admin/events/#{inserted_event.id}/edit")}
  end

  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaAdded{agenda: agenda} = event},
        socket
      ) do
    {:noreply,
     socket
     |> stream_insert(:agendas, agenda)}
  end

  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaUpdated{agenda: agenda} = event},
        socket
      ) do
    {:noreply,
     socket
     |> stream_insert(:agendas, agenda)}
  end

  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaDeleted{agenda: agenda} = event},
        socket
      ) do
    {:noreply,
     socket
     |> stream_delete(:agendas, agenda)}
  end

  def handle_info(
        {YscWeb.Agendas, %Ysc.MessagePassingEvents.AgendaRepositioned{agenda: agenda} = event},
        socket
      ) do
    {:noreply,
     socket
     |> stream_insert(:agendas, agenda, at: agenda.position)}
  end

  def handle_info({Ysc.Agendas, %_event{agenda_item: agenda_item} = event}, socket) do
    send_update(YscWeb.AgendaEditComponent, id: agenda_item.agenda_id, event: event)
    {:noreply, socket}
  end

  @impl true
  def handle_event("publish-event", _, socket) do
    Events.publish_event(socket.assigns.event)

    {:noreply,
     socket |> put_flash(:info, "Event published.") |> push_redirect(to: "/admin/events")}
  end

  @impl true
  def handle_event("unpublish-event", _, socket) do
    Events.unpublish_event(socket.assigns.event)

    {:noreply,
     socket
     |> put_flash(:info, "Event moved back to draft.")
     |> push_redirect(to: "/admin/events/#{socket.assigns.event.id}/new")}
  end

  @impl true
  def handle_event("reposition", %{"id" => id, "new" => new_idx, "old" => _old_idx}, socket) do
    agenda = Agendas.get_agenda!(id)
    Agendas.update_agenda_position(socket.assigns.event.id, agenda, new_idx)
    {:noreply, socket}
  end

  @impl true
  def handle_event("add-agenda", _, socket) do
    Agendas.create_agenda(socket.assigns[:event], %{
      title: "Agenda",
      event_id: socket.assigns[:event].id
    })

    {:noreply, socket}
  end

  def handle_event("delete-agenda", %{"id" => id}, socket) do
    agenda = %Agenda{id: id}
    Agendas.delete_agenda(socket.assigns[:event], agenda)
    {:noreply, socket}
  end

  def handle_event("save", %{"event" => event_params}, socket) do
    event_changeset =
      %Event{}
      |> Event.changeset(event_params)

    case Events.create_event(event_changeset) do
      {:ok, event} ->
        {:noreply, redirect(socket, to: Routes.admin_event_path(socket, :show, event.id))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"event" => event_params}, socket) do
    event_changeset =
      Event.changeset(socket.assigns[:event], event_params) |> Map.put(:action, :validate)

    if event_changeset.valid? do
      Events.update_event(socket.assigns[:event], event_params)
    end

    {:noreply,
     assign_form(socket, event_changeset)
     |> assign(description_length: String.length(event_params["description"] || ""))
     |> assign(:event_title, event_params["title"])
     |> assign(:page_title, event_params["title"])
     |> assign(:start_date, event_params["start_date"])
     |> assign(:end_date, event_params["end_date"])
     |> assign(:start_time, event_params["start_time"])
     |> assign(:end_time, event_params["end_time"])}
  end

  def handle_event("editor-update", %{"raw_body" => raw_body}, socket) do
    changeset = Event.changeset(socket.assigns[:event], %{"raw_details" => raw_body})
    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save-upload", params, socket) do
    IO.inspect(params)
    {:noreply, socket}
  end

  def handle_event("validate-upload", params, socket) do
    IO.inspect(params)
    {:noreply, socket}
  end

  def handle_event("cancel-upload", params, socket) do
    IO.inspect(params)
    {:noreply, socket}
  end

  def handle_event("map-new-marker", %{"lat" => latitude, "long" => longitude} = params, socket) do
    changeset =
      Event.changeset(socket.assigns[:event], %{latitude: latitude, longitude: longitude})

    if changeset.valid? do
      Events.update_event(socket.assigns[:event], %{latitude: latitude, longitude: longitude})
    end

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_info({:updated_event, data}, socket) do
    # Handle the message and update the socket as needed
    # For example, you might want to update the event changeset
    {:noreply, assign(socket, start_date: data[:start_date], end_date: data[:end_date])}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "event")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp format_date(nil), do: ""
  defp format_date(""), do: ""

  defp format_date(dt) when is_binary(dt) do
    Timex.parse!(dt, "{ISO:Extended}")
  end

  defp format_date(dt), do: dt

  defp format_time(nil), do: nil
  defp format_time(""), do: nil

  defp format_time(time) when is_binary(time) do
    case Timex.parse(time, "%H:%M:%S", :strftime) do
      {:ok, time} -> time
      {:error, _} -> Timex.parse!(time, "%H:%M", :strftime)
    end
  end

  defp format_time(time), do: time

  defp description_length(nil), do: 0
  defp description_length(description), do: String.length(description)

  defp event_state_to_badge_style(:draft), do: "sky"
  defp event_state_to_badge_style(:scheduled), do: "yellow"
  defp event_state_to_badge_style(:published), do: "green"
  defp event_state_to_badge_style(:cancelled), do: "orange"
  defp event_state_to_badge_style(:deleted), do: "red"
  defp event_state_to_badge_style(_), do: "default"

  defp schedule_button_text(:scheduled), do: "Scheduled"
  defp schedule_button_text(_), do: "Schedule"
end
