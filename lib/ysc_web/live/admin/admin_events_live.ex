defmodule YscWeb.AdminEventsLive do
  use YscWeb, :live_view

  alias Ysc.Events

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
      <div class="flex justify-between py-6">
        <h1 class="text-2xl font-semibold leading-8 text-zinc-800">
          Events
        </h1>

        <.button phx-click={JS.navigate(~p"/admin/events/new")}>
          <.icon name="hero-calendar" class="w-5 h-5 -mt-1" /><span class="ms-1">New Event</span>
        </.button>
      </div>

      <div class="w-full pt-4">
        <div id="admin-event-filters" class="pb-4 flex">
          <.dropdown id="filter-events-dropdown" class="group hover:bg-zinc-100">
            <:button_block>
              <.icon
                name="hero-funnel"
                class="mr-1 text-zinc-600 w-5 h-5 group-hover:text-zinc-800 -mt-0.5"
              /> Filters
            </:button_block>

            <div class="w-full px-4 py-3">
              <.filter_form
                fields={[
                  state: [
                    label: "State",
                    type: "checkgroup",
                    multiple: true,
                    op: :in,
                    options: [
                      {"Published", :published},
                      {"Draft", :draft},
                      {"Deleted", :deleted},
                      {"Scheduled", :scheduled},
                      {"Cancelled", :cancelled}
                    ]
                  ],
                  organizer_id: [
                    label: "Organizer",
                    type: "checkgroup",
                    multiple: true,
                    op: :in,
                    options: @author_filter
                  ]
                ]}
                meta={@meta}
                id="events-filter-form"
              />
            </div>

            <div class="px-4 py-4">
              <button
                class="rounded hover:bg-zinc-100 py-2 px-3 transition duration-200 ease-in-out text-sm font-semibold leading-6 text-zinc-800 active:text-zinc-100/80 w-full"
                phx-click={JS.navigate(~p"/admin/events")}
              >
                <.icon name="hero-x-circle" class="w-5 h-5 -mt-1" /> Clear filters
              </button>
            </div>
          </.dropdown>
        </div>

        <Flop.Phoenix.table
          id="admin_events_list"
          items={@streams.events}
          meta={@meta}
          path={~p"/admin/events"}
        >
          <:col :let={{_, event}} label="Title" field={:title}>
            <p class="text-sm font-semibold">
              <%= event.title %>
            </p>
          </:col>

          <:col :let={{_, event}} label="Event Date" field={:start_date}>
            <%= format_date(event.start_date) %>
          </:col>

          <:col :let={{_, event}} label="Author" field={:author_name}>
            <%= "#{String.capitalize(event.organizer.first_name)} #{String.capitalize(event.organizer.last_name)}" %>
          </:col>

          <:col :let={{_, event}} label="State" field={:state}>
            <.badge type={event_state_to_badge_style(event.state)}>
              <%= String.capitalize("#{event.state}") %>
            </.badge>
          </:col>

          <:col :let={{_, event}} label="Created" field={:inserted_at}>
            <%= format_date(event.inserted_at) %>
          </:col>

          <:action :let={{_, event}} label="Action">
            <button
              phx-click={JS.navigate(~p"/admin/events/#{event.id}/edit")}
              class="text-blue-600 font-semibold hover:underline cursor-pointer"
            >
              Edit
            </button>
          </:action>
        </Flop.Phoenix.table>
      </div>
    </.side_menu>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Events")
     |> assign(:active_page, :events), temporary_assigns: [author_filter: []]}
  end

  def handle_params(params, _uri, socket) do
    case Events.list_events_paginated(params) do
      {:ok, {events, meta}} ->
        author_filter = Events.get_all_authors()

        {:noreply,
         assign(socket, meta: meta)
         |> assign(author_filter: author_filter)
         |> stream(:events, events, reset: true)}

      {:error, _meta} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/events")}
    end
  end

  def handle_event("update-filter", params, socket) do
    params = Map.delete(params, "_target")

    updated_filters =
      Enum.reduce(params["filters"], %{}, fn {k, v}, red ->
        Map.put(red, k, maybe_update_filter(v))
      end)

    new_params = Map.replace(params, "filters", updated_filters)

    {:noreply, push_patch(socket, to: ~p"/admin/events?#{new_params}")}
  end

  defp event_state_to_badge_style(:draft), do: "sky"
  defp event_state_to_badge_style(:scheduled), do: "yellow"
  defp event_state_to_badge_style(:published), do: "green"
  defp event_state_to_badge_style(:cancelled), do: "orange"
  defp event_state_to_badge_style(:deleted), do: "red"
  defp event_state_to_badge_style(_), do: "default"

  defp format_date(nil), do: "n/a"
  defp format_date(date), do: Timex.format!(date, "{Mshort} {D}, {YYYY}")

  defp maybe_update_filter(%{"value" => [""]} = filter), do: Map.replace(filter, "value", "")
  defp maybe_update_filter(filter), do: filter
end
