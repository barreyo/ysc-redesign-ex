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
      <div class="flex py-6 flex-col space-y-1">
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

        <div :if={@start_date != nil} class="flex flex-row space-x-1 items-center">
          <.icon name="hero-calendar-days" class="text-zinc-600" />
          <p :if={@end_date == nil || @end_date == @start_date} class="text-zinc-600 text-sm">
            <%= Timex.format!(@start_date, "%a, %b %d, %Y", :strftime) %>
          </p>

          <p :if={@end_date != nil && @end_date != @start_date} class="text-zinc-600 text-sm">
            <%= Timex.format!(@start_date, "%a, %b %d, %Y", :strftime) %> - <%= Timex.format!(
              @end_date,
              "%a, %b %d, %Y",
              :strftime
            ) %>
          </p>

          <p
            :if={@start_time != nil && @end_time != nil && @start_time != "" && @end_time != ""}
            class="text-sm text-zinc-400"
          >
            •
          </p>

          <p
            :if={@start_time != nil && @end_time != nil && @start_time != "" && @end_time != ""}
            class="text-zinc-600 text-sm"
          >
            <%= @start_time %> - <%= @end_time %>
          </p>
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

        <div :if={@live_action == :edit} class="relative pb-10">
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
                    start_date_field={@form[:start]}
                    end_date_field={@form[:end]}
                    min={Date.utc_today()}
                  />
                </div>

                <.input type="time" id="start_time" field={@form[:start_time]} label="Start Time*" />
                <.input type="time" id="end_time" field={@form[:end_time]} label="End Time" />
              </div>

              <h3 class="text-lg pt-4 font-medium">Location</h3>
              <div>
                <p>dance</p>
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
                  id="post[raw_details]"
                  field={@form[:raw_details]}
                  post-id={@event.id}
                  phx-hook="TrixHook"
                />
                <div id="richtext" phx-update="ignore">
                  <trix-editor
                    input="post[raw_details]"
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
     |> assign(:start_date, event.start)
     |> assign(:end_date, event.end)
     |> assign(:start_time, nil)
     |> assign(:end_time, nil)
     |> assign(:state, :draft)
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
  def handle_event("reposition", %{"id" => id, "new" => new_idx, "old" => _old_idx}, socket) do
    agenda = Agendas.get_agenda!(id)
    Agendas.update_agenda_position(socket.assigns.event.id, agenda, new_idx)
    {:noreply, socket}
  end

  @impl true
  def handle_event("add-agenda", _, socket) do
    Agendas.create_agenda(socket.assigns[:event], %{
      title: "Untitled Agenda",
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

    Events.update_event(socket.assigns[:event], event_params)

    {:noreply,
     assign_form(socket, event_changeset)
     |> assign(description_length: String.length(event_params["description"] || ""))
     |> assign(:event_title, event_params["title"])
     |> assign(:page_title, event_params["title"])
     |> assign(:start_time, event_params["start_time"])
     |> assign(:end_time, event_params["end_time"])}
  end

  def handle_info({:updated_event, data}, socket) do
    # Handle the message and update the socket as needed
    # For example, you might want to update the event changeset
    IO.inspect(data)

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

  defp parse_start_end(%{start_date: nil, end_date: nil} = params) do
    params
  end

  defp parse_start_end(%{start_date: value, end_date: nil} = params) do
    Map.put(params, "start", Timex.parse!(value, "%Y-%m-%d"))
  end

  defp parse_start_end(%{start_date: nil, end_date: value} = params) do
    Map.put(params, "end", Timex.parse!(value, "%Y-%m-%d"))
  end

  defp parse_start_end(event_params) do
    Map.put(event_params, "start", Timex.parse!(event_params["start_date"], "%Y-%m-%d"))
    |> Map.put("end", Timex.parse!(event_params["end_date"], "%Y-%m-%d"))
  end

  defp save_agendas_and_items(event_id, agendas) do
    for agenda_params <- agendas do
      agenda =
        %Agenda{}
        |> Agenda.changeset(Map.put(agenda_params, "event_id", event_id))
        |> Repo.insert!()

      for item_params <- agenda_params["items"] || [] do
        %AgendaItem{}
        |> AgendaItem.changeset(Map.put(item_params, "agenda_id", agenda.id))
        |> Repo.insert!()
      end
    end
  end

  defp description_length(nil), do: 0
  defp description_length(description), do: String.length(description)

  defp event_state_to_badge_style(:draft), do: "sky"
  defp event_state_to_badge_style(:scheduled), do: "yellow"
  defp event_state_to_badge_style(:published), do: "green"
  defp event_state_to_badge_style(:cancelled), do: "orange"
  defp event_state_to_badge_style(:deleted), do: "red"
  defp event_state_to_badge_style(_), do: "default"
end
