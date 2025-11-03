defmodule YscWeb.EventDetailsLive do
  use YscWeb, :live_view

  alias HtmlSanitizeEx.Scrubber

  alias Ysc.Events
  alias Ysc.Events.Event
  alias Ysc.Repo

  alias Ysc.Agendas

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10">
      <div class="max-w-screen-lg mx-auto flex flex-wrap px-4 space-y-10 flex-col relative">
        <.live_component
          id={"event-cover-#{@event.id}"}
          module={YscWeb.Components.Image}
          image_id={@event.image_id}
        />

        <div class="relative flex flex-col md:flex-row flex-grow justify-center md:justify-between space-x-0 md:space-x-4">
          <div class="max-w-xl space-y-10 md:mx-0 mx-auto">
            <div class="space-y-1">
              <p :if={@event.state == :cancelled} class="font-semibold text-red-600">
                // This event has been cancelled //
              </p>

              <div :if={@event.state != :cancelled && event_at_capacity?(@event)}>
                <.badge type="red">SOLD OUT</.badge>
              </div>

              <p
                :if={
                  @event.start_date != nil && @event.start_date != "" && @event.state != :cancelled
                }
                class="font-semibold text-zinc-600"
              >
                <%= format_start_date(@event.start_date) %>
              </p>

              <h2
                :if={@event.title != nil && @event.title != ""}
                class="text-4xl font-bold leading-10"
              >
                <%= @event.title %>
              </h2>

              <p
                :if={@event.description != nil && @event.description != ""}
                class="font-semibold text-zinc-600 pt-2"
              >
                <%= @event.description %>
              </p>
            </div>
            <!-- User's Existing Tickets -->
            <div :if={@current_user != nil && length(@user_tickets) > 0} class="space-y-4">
              <h3 class="text-zinc-800 text-2xl font-semibold">Your Tickets</h3>
              <div class="">
                <div class="flex items-center mb-3">
                  <.icon name="hero-check-circle" class="text-green-500 w-5 h-5 me-2" />
                  <h4 class="text-zinc-800 font-semibold">Your confirmed tickets for this event</h4>
                </div>
                <div class="space-y-2">
                  <%= for {tier_name, tickets} <- group_tickets_by_tier(@user_tickets) do %>
                    <div class="flex justify-between items-center bg-zinc-50 rounded p-3 border border-zinc-200">
                      <div>
                        <p class="font-medium text-zinc-900">
                          <%= length(tickets) %>x <%= tier_name %>
                        </p>
                        <p class="text-sm text-zinc-500">
                          <%= if length(tickets) == 1 do %>
                            Ticket #<%= List.first(tickets).reference_id %>
                          <% else %>
                            <%= length(tickets) %> confirmed tickets
                          <% end %>
                        </p>
                      </div>
                      <div class="text-right">
                        <p class="font-semibold text-zinc-900">
                          <%= cond do %>
                            <% List.first(tickets).ticket_tier.type == "donation" || List.first(tickets).ticket_tier.type == :donation -> %>
                              Donation
                            <% List.first(tickets).ticket_tier.price == nil -> %>
                              Free
                            <% Money.zero?(List.first(tickets).ticket_tier.price) -> %>
                              Free
                            <% true -> %>
                              <%= case Money.to_string(List.first(tickets).ticket_tier.price) do
                                {:ok, amount} -> amount
                                {:error, _} -> "Error"
                              end %>
                          <% end %>
                        </p>
                        <p class="text-xs text-green-600 font-medium">Confirmed</p>
                      </div>
                    </div>
                  <% end %>
                </div>
                <p class="text-sm text-zinc-600 mt-3">
                  You may purchase additional tickets if there are any available.
                </p>
              </div>
            </div>

            <div class="space-y-4">
              <h3 class="text-zinc-800 text-2xl font-semibold">Date and Time</h3>

              <div class="items-center flex text-zinc-600 text-semibold">
                <.icon name="hero-calendar" class="me-1" />
                <%= Ysc.Events.DateTimeFormatter.format_datetime(%{
                  start_date: format_date(@event.start_date),
                  start_time: format_time(@event.start_time),
                  end_date: format_date(@event.end_date),
                  end_time: format_time(@event.end_time)
                }) %>
              </div>

              <div>
                <add-to-calendar-button
                  name={@event.title}
                  startDate={date_for_add_to_cal(@event.start_date)}
                  {if get_end_date_for_calendar(@event), do: [endDate: date_for_add_to_cal(get_end_date_for_calendar(@event))], else: []}
                  options="'Apple','Google','iCal','Outlook.com','Yahoo'"
                  startTime={@event.start_time}
                  {if get_end_time_for_calendar(@event), do: [endTime: get_end_time_for_calendar(@event)], else: []}
                  timeZone="America/Los_Angeles"
                  location={@event.location_name}
                  size="5"
                  lightMode="bodyScheme"
                >
                </add-to-calendar-button>
              </div>
            </div>

            <div
              :if={
                (@event.location_name != "" && @event.location_name != nil) ||
                  (@event.address != nil && @event.address != "")
              }
              class="space-y-4"
            >
              <h3 class="text-zinc-800 text-2xl font-semibold">Location</h3>
              <p :if={@event.location_name != nil && @event.location_name != ""} class="font-semibold">
                <%= @event.location_name %>
              </p>
              <p :if={@event.address != nil && @event.address != ""}><%= @event.address %></p>

              <div
                :if={
                  @event.latitude != nil && @event.longitude != nil && @event.latitude != "" &&
                    @event.longitude != ""
                }
                class="space-y-4"
              >
                <button
                  class="transition duration-200 ease-in-out hover:text-blue-800 text-blue-600 font-bold mt-2"
                  phx-click={
                    JS.toggle_class("hidden",
                      to: "#event-map"
                    )
                    |> JS.toggle_class("rotate-180",
                      to: "#map-chevron"
                    )
                    |> JS.push("toggle-map")
                  }
                >
                  <span id="map-button-text">Show Map</span>
                  <.icon
                    name="hero-chevron-down"
                    id="map-chevron"
                    class="ms-1 w-5 h-5 transition-transform duration-200 -mt-0.5"
                  />
                </button>

                <div id="event-map" class="hidden">
                  <.live_component
                    id={"#{@event.id}-map"}
                    module={YscWeb.Components.MapComponent}
                    event_id={@event.id}
                    latitude={@event.latitude}
                    longitude={@event.longitude}
                    locked={true}
                    class="max-w-screen-lg"
                  />

                  <div>
                    <ul class="flex flex-row items-center justify-center py-4 space-x-8">
                      <li>
                        <a
                          href={"https://maps.google.com/?saddr=Current+Location&daddr=#{@event.latitude},#{@event.longitude}&dirflg=w"}
                          target="_blank"
                          class="group hover:blue-600 hover:fill-blue-600 transition ease-in-out duration-200"
                        >
                          <svg
                            stroke-width="0"
                            viewBox="0 0 320 512"
                            xmlns="http://www.w3.org/2000/svg"
                            class="w-6 h-6 text-zinc-600 fill-zinc-600 group-hover:fill-blue-600 group-hover:text-blue-600 transition ease-in-out duration-200"
                          >
                            <path d="M208 96c26.5 0 48-21.5 48-48S234.5 0 208 0s-48 21.5-48 48 21.5 48 48 48zm94.5 149.1l-23.3-11.8-9.7-29.4c-14.7-44.6-55.7-75.8-102.2-75.9-36-.1-55.9 10.1-93.3 25.2-21.6 8.7-39.3 25.2-49.7 46.2L17.6 213c-7.8 15.8-1.5 35 14.2 42.9 15.6 7.9 34.6 1.5 42.5-14.3L81 228c3.5-7 9.3-12.5 16.5-15.4l26.8-10.8-15.2 60.7c-5.2 20.8.4 42.9 14.9 58.8l59.9 65.4c7.2 7.9 12.3 17.4 14.9 27.7l18.3 73.3c4.3 17.1 21.7 27.6 38.8 23.3 17.1-4.3 27.6-21.7 23.3-38.8l-22.2-89c-2.6-10.3-7.7-19.9-14.9-27.7l-45.5-49.7 17.2-68.7 5.5 16.5c5.3 16.1 16.7 29.4 31.7 37l23.3 11.8c15.6 7.9 34.6 1.5 42.5-14.3 7.7-15.7 1.4-35.1-14.3-43zM73.6 385.8c-3.2 8.1-8 15.4-14.2 21.5l-50 50.1c-12.5 12.5-12.5 32.8 0 45.3s32.7 12.5 45.2 0l59.4-59.4c6.1-6.1 10.9-13.4 14.2-21.5l13.5-33.8c-55.3-60.3-38.7-41.8-47.4-53.7l-20.7 51.5z">
                            </path>
                          </svg>
                        </a>
                      </li>

                      <li>
                        <a
                          href={"https://www.google.com/maps?saddr=Current+Location&daddr=#{@event.latitude},#{@event.longitude}&mode=driving"}
                          target="_blank"
                          class="group hover:blue-600 hover:fill-blue-600 transition ease-in-out duration-200"
                        >
                          <svg
                            stroke-width="0"
                            viewBox="0 0 512 512"
                            xmlns="http://www.w3.org/2000/svg"
                            class="w-6 h-6 text-zinc-600 fill-zinc-600 group-hover:fill-blue-600 group-hover:text-blue-600 transition ease-in-out duration-200"
                          >
                            <path d="M499.99 176h-59.87l-16.64-41.6C406.38 91.63 365.57 64 319.5 64h-127c-46.06 0-86.88 27.63-103.99 70.4L71.87 176H12.01C4.2 176-1.53 183.34.37 190.91l6 24C7.7 220.25 12.5 224 18.01 224h20.07C24.65 235.73 16 252.78 16 272v48c0 16.12 6.16 30.67 16 41.93V416c0 17.67 14.33 32 32 32h32c17.67 0 32-14.33 32-32v-32h256v32c0 17.67 14.33 32 32 32h32c17.67 0 32-14.33 32-32v-54.07c9.84-11.25 16-25.8 16-41.93v-48c0-19.22-8.65-36.27-22.07-48H494c5.51 0 10.31-3.75 11.64-9.09l6-24c1.89-7.57-3.84-14.91-11.65-14.91zm-352.06-17.83c7.29-18.22 24.94-30.17 44.57-30.17h127c19.63 0 37.28 11.95 44.57 30.17L384 208H128l19.93-49.83zM96 319.8c-19.2 0-32-12.76-32-31.9S76.8 256 96 256s48 28.71 48 47.85-28.8 15.95-48 15.95zm320 0c-19.2 0-48 3.19-48-15.95S396.8 256 416 256s32 12.76 32 31.9-12.8 31.9-32 31.9z">
                            </path>
                          </svg>
                        </a>
                      </li>

                      <li>
                        <a
                          class="group hover:blue-800 hover:fill-blue-800 transition ease-in-out duration-200"
                          target="_blank"
                          href={"https://maps.google.com/?saddr=Current+Location&daddr=#{@event.latitude},#{@event.longitude}&mode=transit&dirflg=r"}
                        >
                          <svg
                            stroke-width="0"
                            viewBox="0 0 576 512"
                            xmlns="http://www.w3.org/2000/svg"
                            class="w-6 h-6 text-zinc-600 fill-zinc-600 group-hover:fill-blue-600 group-hover:text-blue-600 transition ease-in-out duration-200"
                          >
                            <path d="M288 0C422.4 0 512 35.2 512 80l0 16 0 32c17.7 0 32 14.3 32 32l0 64c0 17.7-14.3 32-32 32l0 160c0 17.7-14.3 32-32 32l0 32c0 17.7-14.3 32-32 32l-32 0c-17.7 0-32-14.3-32-32l0-32-192 0 0 32c0 17.7-14.3 32-32 32l-32 0c-17.7 0-32-14.3-32-32l0-32c-17.7 0-32-14.3-32-32l0-160c-17.7 0-32-14.3-32-32l0-64c0-17.7 14.3-32 32-32c0 0 0 0 0 0l0-32s0 0 0 0l0-16C64 35.2 153.6 0 288 0zM128 160l0 96c0 17.7 14.3 32 32 32l112 0 0-160-112 0c-17.7 0-32 14.3-32 32zM304 288l112 0c17.7 0 32-14.3 32-32l0-96c0-17.7-14.3-32-32-32l-112 0 0 160zM144 400a32 32 0 1 0 0-64 32 32 0 1 0 0 64zm288 0a32 32 0 1 0 0-64 32 32 0 1 0 0 64zM384 80c0-8.8-7.2-16-16-16L208 64c-8.8 0-16 7.2-16 16s7.2 16 16 16l160 0c8.8 0 16-7.2 16-16z">
                            </path>
                          </svg>
                        </a>
                      </li>

                      <li>
                        <a
                          class="group hover:blue-800 hover:fill-blue-800 transition ease-in-out duration-200"
                          target="_blank"
                          href={"https://www.google.com/maps?saddr=Current+Location&daddr=#{@event.latitude},#{@event.longitude}&mode=bicycling&dirflg=b"}
                        >
                          <svg
                            stroke-width="0"
                            viewBox="0 0 640 512"
                            xmlns="http://www.w3.org/2000/svg"
                            class="w-6 h-6 text-zinc-600 fill-zinc-600 group-hover:fill-blue-600 group-hover:text-blue-600 transition ease-in-out duration-200"
                          >
                            <path d="M512.509 192.001c-16.373-.064-32.03 2.955-46.436 8.495l-77.68-125.153A24 24 0 0 0 368.001 64h-64c-8.837 0-16 7.163-16 16v16c0 8.837 7.163 16 16 16h50.649l14.896 24H256.002v-16c0-8.837-7.163-16-16-16h-87.459c-13.441 0-24.777 10.999-24.536 24.437.232 13.044 10.876 23.563 23.995 23.563h48.726l-29.417 47.52c-13.433-4.83-27.904-7.483-42.992-7.52C58.094 191.83.412 249.012.002 319.236-.413 390.279 57.055 448 128.002 448c59.642 0 109.758-40.793 123.967-96h52.033a24 24 0 0 0 20.406-11.367L410.37 201.77l14.938 24.067c-25.455 23.448-41.385 57.081-41.307 94.437.145 68.833 57.899 127.051 126.729 127.719 70.606.685 128.181-55.803 129.255-125.996 1.086-70.941-56.526-129.72-127.476-129.996zM186.75 265.772c9.727 10.529 16.673 23.661 19.642 38.228h-43.306l23.664-38.228zM128.002 400c-44.112 0-80-35.888-80-80s35.888-80 80-80c5.869 0 11.586.653 17.099 1.859l-45.505 73.509C89.715 331.327 101.213 352 120.002 352h81.3c-12.37 28.225-40.562 48-73.3 48zm162.63-96h-35.624c-3.96-31.756-19.556-59.894-42.383-80.026L237.371 184h127.547l-74.286 120zm217.057 95.886c-41.036-2.165-74.049-35.692-75.627-76.755-.812-21.121 6.633-40.518 19.335-55.263l44.433 71.586c4.66 7.508 14.524 9.816 22.032 5.156l13.594-8.437c7.508-4.66 9.817-14.524 5.156-22.032l-44.468-71.643a79.901 79.901 0 0 1 19.858-2.497c44.112 0 80 35.888 80 80-.001 45.54-38.252 82.316-84.313 79.885z">
                            </path>
                          </svg>
                        </a>
                      </li>
                    </ul>
                  </div>
                </div>
              </div>
            </div>

            <div :if={length(@agendas) > 0} class="space-y-4">
              <h3 class="text-zinc-800 text-2xl font-semibold">Agenda</h3>

              <div :if={length(@agendas) > 1} class="py-4">
                <ul class="flex-row flex text-sm font-medium text-zinc-600 space-x-2">
                  <%= for agenda <- @agendas do %>
                    <li id={"agenda-selector-#{agenda.id}"}>
                      <button
                        phx-click="set-active-agenda"
                        phx-value-id={agenda.id}
                        class={[
                          "inline-flex items-center px-4 py-3 rounded w-full",
                          agenda.id == @active_agenda && "active text-zinc-100 bg-blue-600",
                          agenda.id != @active_agenda &&
                            "text-zinc-600 hover:bg-zinc-100 hover:text-zinc-800"
                        ]}
                      >
                        <%= agenda.title %>
                      </button>
                    </li>
                  <% end %>
                </ul>
              </div>

              <%= for agenda <- @agendas do %>
                <div :if={agenda.id == @active_agenda} class="space-y-3">
                  <%= for agenda_item <- agenda.agenda_items do %>
                    <div
                      class="rounded py-3 px-4"
                      style={"background-color: #{ULIDColor.generate_color_from_idx(agenda_item.position)}"}
                    >
                      <div
                        class="border-l border-l-2"
                        style={"border-left-color: #{ULIDColor.generate_color_from_idx(agenda_item.position, :dark)}"}
                      >
                        <div class="px-2">
                          <p class="text-sm font-semibold text-zinc-600">
                            <%= format_start_end(agenda_item.start_time, agenda_item.end_time) %>
                          </p>
                          <p class="text-zinc-900 text-lg font-semibold"><%= agenda_item.title %></p>
                          <p :if={agenda_item.description != nil} class="text-zinc-600 text-sm mt-2">
                            <%= agenda_item.description %>
                          </p>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <div class="space-y-4">
              <h3 class="text-zinc-800 text-2xl font-semibold">Details</h3>
              <div class="prose prose-zinc prose-base prose-a:text-blue-600 max-w-xl pb-10">
                <div id="article-body" class="post-render">
                  <%= raw(event_body(@event)) %>
                </div>
              </div>
            </div>
          </div>

          <div
            :if={@event.state != :cancelled}
            class="fixed md:shadow-md bottom-0 w-full md:w-1/3 md:sticky bg-white rounded border border-zinc-200 h-32 md:h-36 md:top-8 right-0 px-4 py-3 z-40 flex text-center flex flex-col justify-center space-y-4"
          >
            <div class="flex flex-col items-center justify-center">
              <p class={[
                "font-semibold text-lg",
                if event_at_capacity?(@event) do
                  "line-through"
                else
                  ""
                end
              ]}>
                <%= @event.pricing_info.display_text %>
              </p>
              <p :if={@event.start_date != nil} class="text-sm text-zinc-600">
                <%= format_start_date(@event.start_date) %>
              </p>
            </div>

            <div :if={@current_user == nil} class="w-full">
              <p class="text-sm text-red-700 px-2 py-1 bg-red-50 rounded mb-2 border border-red-100 text-center">
                <.icon name="hero-exclamation-circle" class="text-red-400 w-5 h-5 me-1 -mt-0.5" />Only members can access tickets
              </p>
            </div>

            <div
              :if={@current_user != nil && !@active_membership? && has_ticket_tiers?(@event.id)}
              class="w-full"
            >
              <p class="text-sm text-orange-700 px-2 py-1 bg-orange-50 rounded mb-2 border border-orange-100 text-center">
                <.icon name="hero-exclamation-circle" class="text-orange-400 w-5 h-5 me-1 -mt-0.5" />Active membership required to purchase tickets
              </p>
            </div>

            <%= if has_ticket_tiers?(@event.id) do %>
              <%= if event_in_past?(@event) do %>
                <div class="w-full text-center py-3">
                  <div class="text-red-600 mb-2">
                    <.icon name="hero-clock" class="w-8 h-8 mx-auto" />
                  </div>
                  <p class="text-red-700 font-medium text-sm">Event has ended</p>
                  <p class="text-red-600 text-xs mt-1">Tickets are no longer available</p>
                </div>
              <% else %>
                <%= if event_at_capacity?(@event) do %>
                  <div class="w-full">
                    <.tooltip tooltip_text="This event is sold out">
                      <.button
                        :if={@current_user != nil && @active_membership?}
                        class="w-full opacity-50 cursor-not-allowed"
                        disabled
                      >
                        <.icon name="hero-ticket" class="me-2 -mt-0.5" />Sold Out
                      </.button>
                    </.tooltip>
                  </div>
                <% else %>
                  <.button
                    :if={@current_user != nil && @active_membership?}
                    class="w-full"
                    phx-click="open-ticket-modal"
                  >
                    <.icon name="hero-ticket" class="me-2 -mt-0.5" />Get Tickets
                  </.button>
                <% end %>
              <% end %>
            <% else %>
              <div class="w-full text-center py-1">
                <p class="font-bold text-green-800 text-sm">No registration required</p>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    <!-- Ticket Selection Modal -->
    <.modal
      :if={@show_ticket_modal}
      id="ticket-modal"
      show
      on_cancel={JS.push("close-ticket-modal")}
      max_width="max-w-6xl"
    >
      <div class="flex flex-col lg:flex-row gap-8 min-h-[600px]">
        <!-- Left Panel: Ticket Tiers -->
        <div class="lg:w-2/3 space-y-8">
          <div class="w-full border-b border-zinc-200 pb-4">
            <h2 class="text-2xl font-semibold"><%= @event.title %></h2>
            <p :if={@event.start_date != nil} class="text-sm text-zinc-600">
              <%= format_start_date(@event.start_date) %>
            </p>
          </div>

          <div class="space-y-4 h-full lg:overflow-y-auto lg:max-h-[600px] lg:px-4">
            <%= for ticket_tier <- get_ticket_tiers(@event.id) do %>
              <% is_donation = ticket_tier.type == "donation" || ticket_tier.type == :donation %>
              <% available = get_available_quantity(ticket_tier) %>
              <% is_event_at_capacity = event_at_capacity?(@event) %>
              <% is_sold_out = if is_donation, do: false, else: available == 0 || is_event_at_capacity %>
              <% is_on_sale = if is_donation, do: true, else: tier_on_sale?(ticket_tier) %>
              <% is_sale_ended = if is_donation, do: false, else: tier_sale_ended?(ticket_tier) %>
              <% days_until_sale = if is_donation, do: nil, else: days_until_sale_starts(ticket_tier) %>
              <% is_pre_sale = if is_donation, do: false, else: not is_on_sale && !is_sale_ended %>
              <% has_selected_tickets = get_ticket_quantity(@selected_tickets, ticket_tier.id) > 0 %>
              <div class={[
                "border rounded-lg p-6 transition-all duration-200",
                cond do
                  is_sold_out -> "border-zinc-200 bg-zinc-50 opacity-60"
                  is_sale_ended -> "border-zinc-200 bg-zinc-50 opacity-60"
                  is_pre_sale -> "border-zinc-200 bg-zinc-50 opacity-70"
                  has_selected_tickets -> "border-blue-500 bg-blue-50"
                  true -> "border-zinc-200 bg-white"
                end
              ]}>
                <div class="flex justify-between items-start mb-4">
                  <div>
                    <h4 class="font-semibold text-lg text-zinc-900"><%= ticket_tier.name %></h4>
                    <p :if={ticket_tier.description} class="text-base text-zinc-600 mt-2">
                      <%= ticket_tier.description %>
                    </p>
                  </div>
                  <div class="text-right">
                    <p
                      :if={ticket_tier.type != "donation" && ticket_tier.type != :donation}
                      class={[
                        "font-semibold text-xl",
                        if is_event_at_capacity do
                          "line-through"
                        else
                          ""
                        end
                      ]}
                    >
                      <%= case ticket_tier.type do %>
                        <% "free" -> %>
                          Free
                        <% _ -> %>
                          <%= format_price(ticket_tier.price) %>
                      <% end %>
                    </p>
                    <p
                      :if={ticket_tier.type != "donation" && ticket_tier.type != :donation}
                      class={[
                        "text-base text-sm",
                        cond do
                          is_sold_out -> "text-red-500 font-semibold"
                          is_sale_ended -> "text-red-500 font-semibold"
                          is_pre_sale -> "text-blue-500 font-semibold"
                          true -> "text-zinc-500"
                        end
                      ]}
                    >
                      <%= cond do %>
                        <% is_sale_ended -> %>
                          Sale ended
                        <% is_pre_sale -> %>
                          Sale starts in <%= days_until_sale %> <%= if days_until_sale == 1,
                            do: "day",
                            else: "days" %>
                        <% is_event_at_capacity -> %>
                          Sold Out (Event at capacity)
                        <% available == :unlimited -> %>
                          Unlimited
                        <% available == 0 -> %>
                          Sold Out
                        <% true -> %>
                          <%= "#{available} remaining" %>
                      <% end %>
                    </p>
                  </div>
                </div>

                <%= if ticket_tier.type == "donation" || ticket_tier.type == :donation do %>
                  <!-- Donation Amount Input -->
                  <div class="flex flex-col space-y-3 mt-4">
                    <div class="flex items-center justify-end">
                      <div class="flex items-center space-x-3 w-full sm:w-auto">
                        <label class="text font-semibold text-zinc-700 whitespace-nowrap">
                          Donation Amount:
                        </label>
                        <div class="flex items-center border border-zinc-300 rounded-lg px-3 py-2 flex-1 sm:flex-initial">
                          <span class="text-zinc-800 me-2">$</span>
                          <input
                            type="text"
                            id={"donation-amount-#{ticket_tier.id}"}
                            name={"donation_amount_#{ticket_tier.id}"}
                            phx-hook="MoneyInput"
                            data-tier-id={ticket_tier.id}
                            value={format_donation_amount(@selected_tickets, ticket_tier.id)}
                            placeholder="0.00"
                            disabled={false}
                            class="w-full sm:w-32 border-0 focus:ring-0 focus:outline-none text-lg font-medium text-zinc-900 bg-transparent"
                          />
                        </div>
                      </div>
                    </div>
                    <!-- Quick Amount Buttons -->
                    <div class="flex items-center justify-end gap-2">
                      <button
                        type="button"
                        phx-click="set-donation-amount"
                        phx-value-tier-id={ticket_tier.id}
                        phx-value-amount="1000"
                        class="px-3 py-1.5 text-sm font-medium rounded-md border transition-colors border-zinc-300 bg-white text-zinc-700 hover:bg-zinc-50 hover:border-zinc-400"
                      >
                        $10
                      </button>
                      <button
                        type="button"
                        phx-click="set-donation-amount"
                        phx-value-tier-id={ticket_tier.id}
                        phx-value-amount="2500"
                        class="px-3 py-1.5 text-sm font-medium rounded-md border transition-colors border-zinc-300 bg-white text-zinc-700 hover:bg-zinc-50 hover:border-zinc-400"
                      >
                        $25
                      </button>
                      <button
                        type="button"
                        phx-click="set-donation-amount"
                        phx-value-tier-id={ticket_tier.id}
                        phx-value-amount="5000"
                        class="px-3 py-1.5 text-sm font-medium rounded-md border transition-colors border-zinc-300 bg-white text-zinc-700 hover:bg-zinc-50 hover:border-zinc-400"
                      >
                        $50
                      </button>
                    </div>
                  </div>
                  <!-- Donation Disclaimer -->
                  <div class="mt-2 items-center bg-zinc-50 px-3 py-2 rounded-md w-full flex flex-row border border-zinc-200">
                    <.icon name="hero-exclamation-circle" class="text-zinc-600 w-5 h-5 me-1" />
                    <p class="text-sm text-zinc-600">A donation is not a ticket to the event</p>
                  </div>
                <% else %>
                  <!-- Regular Quantity Selector -->
                  <div class="flex items-center justify-end mt-4">
                    <div class="flex items-center space-x-3">
                      <button
                        phx-click="decrease-ticket-quantity"
                        phx-value-tier-id={ticket_tier.id}
                        class={[
                          "w-10 h-10 rounded-full border flex items-center justify-center transition-colors",
                          if(
                            is_sold_out or is_sale_ended or is_pre_sale or
                              get_ticket_quantity(@selected_tickets, ticket_tier.id) == 0
                          ) do
                            "border-zinc-200 bg-zinc-100 text-zinc-400 cursor-not-allowed"
                          else
                            "border-zinc-300 hover:bg-zinc-50 text-zinc-700"
                          end
                        ]}
                        disabled={
                          is_sold_out or is_sale_ended or is_pre_sale or
                            get_ticket_quantity(@selected_tickets, ticket_tier.id) == 0
                        }
                      >
                        <.icon name="hero-minus" class="w-5 h-5" />
                      </button>
                      <span class={[
                        "w-12 text-center font-medium text-lg",
                        if(is_sold_out or is_sale_ended or is_pre_sale,
                          do: "text-zinc-400",
                          else: "text-zinc-900"
                        )
                      ]}>
                        <%= get_ticket_quantity(@selected_tickets, ticket_tier.id) %>
                      </span>
                      <button
                        phx-click="increase-ticket-quantity"
                        phx-value-tier-id={ticket_tier.id}
                        class={[
                          "w-10 h-10 rounded-full border-2 flex items-center justify-center transition-all duration-200 font-semibold",
                          if(
                            is_sold_out or is_sale_ended or is_pre_sale or
                              !can_increase_quantity?(
                                ticket_tier,
                                get_ticket_quantity(@selected_tickets, ticket_tier.id),
                                @selected_tickets,
                                @event
                              )
                          ) do
                            "border-zinc-200 bg-zinc-100 text-zinc-400 cursor-not-allowed"
                          else
                            "border-blue-700 bg-blue-700 hover:bg-blue-800 hover:border-blue-800 text-white"
                          end
                        ]}
                        disabled={
                          is_sold_out or is_sale_ended or is_pre_sale or
                            !can_increase_quantity?(
                              ticket_tier,
                              get_ticket_quantity(@selected_tickets, ticket_tier.id),
                              @selected_tickets,
                              @event
                            )
                        }
                      >
                        <.icon name="hero-plus" class="w-5 h-5" />
                      </button>
                    </div>
                  </div>
                <% end %>
                <!-- Show message for different tier states (exclude donation tiers) -->
                <div :if={!is_donation && is_pre_sale} class="mt-2">
                  <p class="text-sm text-blue-600 bg-blue-50 px-3 py-2 rounded-md border border-blue-200">
                    <.icon name="hero-clock" class="w-4 h-4 inline me-1" />
                    Sale starts <%= Timex.format!(ticket_tier.start_date, "{Mshort} {D}, {YYYY}") %>
                  </p>
                </div>

                <div :if={!is_donation && is_sale_ended} class="mt-2">
                  <p class="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-md border border-red-200">
                    <.icon name="hero-x-circle" class="w-4 h-4 inline me-1" />
                    Sale ended on <%= Timex.format!(ticket_tier.end_date, "{Mshort} {D}, {YYYY}") %>
                  </p>
                </div>

                <div :if={!is_donation && is_sold_out} class="mt-2">
                  <p class="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-md border border-red-200">
                    <.icon name="hero-x-circle" class="w-4 h-4 inline me-1" />
                    This ticket tier is sold out
                  </p>
                </div>

                <div
                  :if={
                    !is_donation && !is_sold_out && !is_pre_sale && !is_sale_ended &&
                      available != :unlimited &&
                      get_ticket_quantity(@selected_tickets, ticket_tier.id) >= available
                  }
                  class="mt-2"
                >
                  <p class="text-sm text-amber-600 bg-amber-50 px-3 py-2 rounded-md border border-amber-200">
                    <.icon name="hero-exclamation-triangle" class="w-4 h-4 inline me-1" />
                    Maximum available tickets selected
                  </p>
                </div>

                <div
                  :if={
                    !is_donation && !is_sold_out && !is_pre_sale && !is_sale_ended &&
                      @event.max_attendees &&
                      calculate_total_selected_tickets(@selected_tickets) >= @event.max_attendees
                  }
                  class="mt-2"
                >
                  <p class="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-md border border-red-200">
                    <.icon name="hero-users" class="w-4 h-4 inline me-1" />
                    Event capacity reached. No more tickets available.
                  </p>
                </div>

                <div :if={!is_donation && is_event_at_capacity} class="mt-2">
                  <p class="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-md border border-red-200">
                    <.icon name="hero-users" class="w-4 h-4 inline me-1" />
                    Event is at capacity (<%= @event.max_attendees %> attendees). All tickets are sold out.
                  </p>
                </div>
              </div>
            <% end %>
          </div>
        </div>
        <!-- Right Panel: Price Breakdown -->
        <div class="lg:w-1/3 space-y-4 justify-between flex flex-col">
          <div class="space-y-4">
            <div class="w-full hidden lg:block">
              <.live_component
                id={"event-checkout-#{@event.id}"}
                module={YscWeb.Components.Image}
                image_id={@event.image_id}
              />
            </div>

            <div>
              <h2 class="text-lg font-semibold mb-6"><%= @event.title %></h2>
              <h3 class="font-semibold mb-2">Order Summary</h3>
            </div>

            <div class="bg-zinc-50 rounded-lg p-6 space-y-4 flex flex-col justify-between">
              <%= if has_any_tickets_selected?(@selected_tickets) do %>
                <%= for {tier_id, amount_or_quantity} <- @selected_tickets, amount_or_quantity > 0 do %>
                  <% ticket_tier = get_ticket_tier_by_id(@event.id, tier_id) %>
                  <div class="flex justify-between text-base">
                    <span>
                      <%= ticket_tier.name %>
                      <%= if ticket_tier.type != "donation" && ticket_tier.type != :donation do %>
                        × <%= amount_or_quantity %>
                      <% end %>
                    </span>
                    <span class={[
                      "font-medium",
                      if event_at_capacity?(@event) do
                        "line-through"
                      else
                        ""
                      end
                    ]}>
                      <%= case ticket_tier.type do %>
                        <% "free" -> %>
                          Free
                        <% "donation" -> %>
                          <%= format_price_from_cents(amount_or_quantity) %>
                        <% :donation -> %>
                          <%= format_price_from_cents(amount_or_quantity) %>
                        <% _ -> %>
                          <%= case Money.mult(ticket_tier.price, amount_or_quantity) do %>
                            <% {:ok, total} -> %>
                              <%= format_price(total) %>
                            <% {:error, _} -> %>
                              $0.00
                          <% end %>
                      <% end %>
                    </span>
                  </div>
                <% end %>
              <% else %>
                <div class="text-center py-4">
                  <div class="text-zinc-400 mb-2">
                    <.icon name="hero-shopping-cart" class="w-8 h-8 mx-auto" />
                  </div>
                  <p class="text-zinc-500 text-sm">No tickets selected</p>
                  <p class="hidden lg:block text-zinc-400 text-xs mt-1">
                    Select tickets from the left to see your order
                  </p>
                </div>
              <% end %>

              <div class="border-t border-zinc-200 pt-4">
                <div class="flex justify-between font-semibold text-lg">
                  <span>Total:</span>
                  <span class={[
                    if event_at_capacity?(@event) do
                      "line-through"
                    else
                      ""
                    end
                  ]}>
                    <%= calculate_total_price(@selected_tickets, @event.id) %>
                  </span>
                </div>
              </div>
            </div>
          </div>

          <div class="mt-8 space-y-4">
            <.button
              class="w-full text-lg py-3"
              phx-click="proceed-to-checkout"
              disabled={!has_any_tickets_selected?(@selected_tickets)}
            >
              <.icon name="hero-shopping-cart" class="me-2 -mt-1" />Proceed to Checkout
            </.button>
          </div>
        </div>
      </div>
    </.modal>
    <!-- Payment Modal -->
    <.modal
      :if={@show_payment_modal}
      id="payment-modal"
      show
      on_cancel={JS.push("close-payment-modal")}
      max_width="max-w-6xl"
    >
      <%= if @checkout_expired do %>
        <!-- Checkout Expired State -->
        <div class="flex flex-col items-center justify-center py-16 space-y-6">
          <div class="text-center">
            <div class="text-red-500 mb-4">
              <.icon name="hero-clock" class="w-16 h-16 mx-auto" />
            </div>
            <h2 class="text-2xl font-semibold text-red-700 mb-2">Checkout Session Expired</h2>
            <p class="text-zinc-600 max-w-md">
              Your checkout session has expired. The tickets you selected may no longer be available.
              Please start over to select your tickets again.
            </p>
          </div>

          <div class="flex space-x-4">
            <.button
              class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-3"
              phx-click="retry-checkout"
            >
              <.icon name="hero-arrow-path" class="w-5 h-5 me-2" /> Try Again
            </.button>
            <.button
              class="bg-zinc-200 text-zinc-800 hover:bg-zinc-300 px-6 py-3"
              phx-click="close-payment-modal"
            >
              Close
            </.button>
          </div>
        </div>
      <% else %>
        <!-- Normal Payment Flow -->
        <div class="flex flex-col lg:flex-row gap-8 min-h-[600px]">
          <!-- Left Panel: Payment Details -->
          <div class="lg:w-2/3 space-y-6">
            <!-- Timer Section -->
            <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
              <div class="flex items-center justify-center space-x-2">
                <.icon name="hero-clock" class="w-5 h-5 text-blue-600" />
                <span class="text-sm font-medium text-blue-800">
                  Time remaining to complete purchase:
                </span>
                <div
                  id="checkout-timer"
                  class="font-bold text-blue-900"
                  phx-hook="CheckoutTimer"
                  data-expires-at={@ticket_order.expires_at}
                >
                  <!-- Timer will be populated by JavaScript -->
                </div>
              </div>
            </div>

            <div class="text-center">
              <h2 class="text-2xl font-semibold">Complete Your Purchase</h2>
              <p class="text-zinc-600 mt-2">Order: <%= @ticket_order.reference_id %></p>
            </div>
            <!-- Stripe Elements Payment Form -->
            <div class="space-y-4">
              <h3 class="font-semibold text-lg">Payment Information</h3>
              <div
                id="payment-element"
                phx-hook="StripeElements"
                data-publicKey={@public_key}
                data-public-key={@public_key}
                data-client-secret={@payment_intent.client_secret}
                data-clientSecret={@payment_intent.client_secret}
              >
                <!-- Stripe Elements will be mounted here -->
              </div>
              <div id="payment-message" class="hidden text-sm"></div>
            </div>

            <div class="flex space-x-4">
              <.button class="flex-1" id="submit-payment">
                Pay <%= calculate_total_price(@selected_tickets, @event.id) %>
              </.button>
              <.button
                class="flex-1 bg-zinc-200 text-zinc-800 hover:bg-zinc-300"
                phx-click="close-payment-modal"
              >
                Cancel
              </.button>
            </div>
          </div>
          <!-- Right Panel: Order Summary -->
          <div class="lg:w-1/3 space-y-4 justify-between flex flex-col">
            <div class="space-y-4">
              <div class="w-full hidden lg:block">
                <.live_component
                  id={"event-checkout-#{@event.id}"}
                  module={YscWeb.Components.Image}
                  image_id={@event.image_id}
                />
              </div>

              <div>
                <h2 class="text-lg font-semibold mb-6"><%= @event.title %></h2>
                <h3 class="font-semibold mb-2">Order Summary</h3>
              </div>

              <div class="bg-zinc-50 rounded-lg p-6 space-y-4">
                <%= if has_any_tickets_selected?(@selected_tickets) do %>
                  <%= for {tier_id, amount_or_quantity} <- @selected_tickets, amount_or_quantity > 0 do %>
                    <% ticket_tier = get_ticket_tier_by_id(@event.id, tier_id) %>
                    <div class="flex justify-between text-base">
                      <span>
                        <%= ticket_tier.name %>
                        <%= if ticket_tier.type != "donation" && ticket_tier.type != :donation do %>
                          × <%= amount_or_quantity %>
                        <% end %>
                      </span>
                      <span class="font-medium">
                        <%= case ticket_tier.type do %>
                          <% "free" -> %>
                            Free
                          <% "donation" -> %>
                            <%= format_price_from_cents(amount_or_quantity) %>
                          <% :donation -> %>
                            <%= format_price_from_cents(amount_or_quantity) %>
                          <% _ -> %>
                            <%= case Money.mult(ticket_tier.price, amount_or_quantity) do %>
                              <% {:ok, total} -> %>
                                <%= format_price(total) %>
                              <% {:error, _} -> %>
                                $0.00
                            <% end %>
                        <% end %>
                      </span>
                    </div>
                  <% end %>
                <% else %>
                  <div class="text-center py-8">
                    <div class="text-zinc-400 mb-2">
                      <.icon name="hero-shopping-cart" class="w-8 h-8 mx-auto" />
                    </div>
                    <p class="text-zinc-500 text-sm">No tickets selected</p>
                  </div>
                <% end %>

                <div class="border-t border-zinc-200 pt-4">
                  <div class="flex justify-between font-semibold text-lg">
                    <span>Total:</span>
                    <span><%= calculate_total_price(@selected_tickets, @event.id) %></span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </.modal>
    <!-- Registration Modal -->
    <.modal
      :if={@show_registration_modal}
      id="registration-modal"
      show
      on_cancel={JS.push("close-registration-modal")}
      max_width="max-w-4xl"
    >
      <div class="flex flex-col space-y-6">
        <div class="text-center">
          <h2 class="text-2xl font-semibold text-zinc-900 mb-2">Ticket Registration</h2>
          <p class="text-zinc-600">
            Please provide details for each ticket that requires registration.
          </p>
        </div>

        <form phx-submit="submit-registration" class="space-y-6">
          <%= for ticket <- @tickets_requiring_registration do %>
            <% ticket_detail =
              Map.get(@ticket_details_form, ticket.id, %{first_name: "", last_name: "", email: ""}) %>
            <div class="border border-zinc-200 rounded-lg p-6 space-y-4">
              <div class="flex items-center justify-between mb-4">
                <div>
                  <h3 class="text-lg font-semibold text-zinc-900">
                    Ticket #<%= ticket.reference_id %>
                  </h3>
                  <p class="text-sm text-zinc-600">
                    <%= ticket.ticket_tier.name %>
                  </p>
                </div>
              </div>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <.input
                    type="text"
                    label="First Name"
                    name={"ticket_#{ticket.id}_first_name"}
                    value={ticket_detail.first_name}
                    required
                  />
                </div>
                <div>
                  <.input
                    type="text"
                    label="Last Name"
                    name={"ticket_#{ticket.id}_last_name"}
                    value={ticket_detail.last_name}
                    required
                  />
                </div>
              </div>
              <div>
                <.input
                  type="email"
                  label="Email"
                  name={"ticket_#{ticket.id}_email"}
                  value={ticket_detail.email}
                  required
                />
              </div>
            </div>
          <% end %>

          <div class="flex space-x-4 pt-4">
            <.button
              type="button"
              class="flex-1 bg-zinc-200 text-zinc-800 hover:bg-zinc-300"
              phx-click="close-registration-modal"
            >
              Cancel
            </.button>
            <.button type="submit" class="flex-1">
              <%= if Money.zero?(@ticket_order.total_amount) do %>
                Continue to Confirmation
              <% else %>
                Continue to Payment
              <% end %>
            </.button>
          </div>
        </form>
      </div>
    </.modal>
    <!-- Free Ticket Confirmation Modal -->
    <.modal
      :if={@show_free_ticket_confirmation}
      id="free-ticket-confirmation-modal"
      show
      on_cancel={JS.push("close-free-ticket-confirmation")}
      max_width="max-w-2xl"
    >
      <div class="flex flex-col items-center justify-center py-12 space-y-6">
        <div class="text-center">
          <div class="text-green-500 mb-4">
            <.icon name="hero-ticket" class="w-16 h-16 mx-auto" />
          </div>
          <h2 class="text-2xl font-semibold text-zinc-900 mb-2">Confirm Your Free Tickets</h2>
          <p class="text-zinc-600 mb-6">
            You've selected free tickets for this event. No payment is required.
          </p>
        </div>
        <!-- Order Summary -->
        <div class="w-full max-w-md bg-zinc-50 rounded-lg p-6">
          <h3 class="text-lg font-semibold text-zinc-900 mb-4">Order Summary</h3>
          <div class="space-y-3">
            <%= for {tier_id, quantity} <- @selected_tickets do %>
              <% tier = Enum.find(@event.ticket_tiers, &(&1.id == tier_id)) %>
              <div class="flex justify-between items-center">
                <div>
                  <p class="font-medium text-zinc-900"><%= tier.name %></p>
                  <p class="text-sm text-zinc-500">Quantity: <%= quantity %></p>
                </div>
                <p class="font-semibold text-zinc-900">Free</p>
              </div>
            <% end %>
          </div>
          <div class="border-t pt-3 mt-4">
            <div class="flex justify-between items-center">
              <p class="text-lg font-semibold text-zinc-900">Total</p>
              <p class="text-lg font-bold text-green-600">Free</p>
            </div>
          </div>
        </div>
        <!-- Action Buttons -->
        <div class="w-full px-8">
          <div class="flex justify-end space-x-4">
            <.button
              class="flex-1 bg-zinc-200 text-zinc-800 hover:bg-zinc-300"
              phx-click="close-free-ticket-confirmation"
            >
              Cancel
            </.button>
            <.button
              phx-click="confirm-free-tickets"
              class="px-6 py-2 flex-1 bg-green-600 hover:bg-green-700"
            >
              Confirm Free Tickets
            </.button>
          </div>
        </div>
      </div>
    </.modal>
    <!-- Order Completion Modal -->
    <.modal
      :if={@show_order_completion}
      id="order-completion-modal"
      show
      on_cancel={JS.push("close-order-completion")}
      max_width="max-w-2xl"
    >
      <div class="flex flex-col items-center justify-center py-12 space-y-6">
        <div class="text-center">
          <div class="text-green-500 mb-4">
            <.icon name="hero-check-circle" class="w-16 h-16 mx-auto" />
          </div>
          <h2 class="text-2xl font-semibold text-zinc-900 mb-2">Order Confirmed!</h2>
        </div>
        <!-- Order Details -->
        <div class="w-full max-w-md bg-zinc-50 rounded-lg p-6">
          <h3 class="text-lg font-semibold text-zinc-900 mb-4">Order Details</h3>
          <div class="space-y-3">
            <div class="flex justify-between">
              <span class="text-zinc-600">Order ID:</span>
              <span class="font-medium"><%= @ticket_order.reference_id %></span>
            </div>
            <div class="flex justify-between">
              <span class="text-zinc-600">Event:</span>
              <span class="font-medium"><%= @event.title %></span>
            </div>
            <div class="flex justify-between">
              <span class="text-zinc-600">Date:</span>
              <span class="font-medium">
                <%= Calendar.strftime(@event.start_date, "%B %d, %Y") %>
              </span>
            </div>
            <div class="flex justify-between">
              <span class="text-zinc-600">Time:</span>
              <span class="font-medium"><%= Calendar.strftime(@event.start_time, "%I:%M %p") %></span>
            </div>
          </div>
        </div>
        <!-- Tickets List -->
        <div class="w-full max-w-md bg-white border rounded-lg p-6">
          <h3 class="text-lg font-semibold text-zinc-900 mb-4">Your Tickets</h3>
          <div class="space-y-3">
            <%= for ticket <- @ticket_order.tickets do %>
              <div class="flex justify-between items-center p-3 bg-zinc-50 rounded">
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
          <div class="border-t pt-3 mt-4">
            <div class="flex justify-between items-center">
              <p class="text-lg font-semibold text-zinc-900">Total</p>
              <p class="text-lg font-bold text-green-600">
                <%= if Money.zero?(@ticket_order.total_amount) do %>
                  Free
                <% else %>
                  <%= case Money.to_string(@ticket_order.total_amount) do
                    {:ok, amount} -> amount
                    {:error, _} -> "Error"
                  end %>
                <% end %>
              </p>
            </div>
          </div>
        </div>
        <!-- Email Notice -->
        <div class="w-full max-w-md bg-blue-50 border border-blue-200 rounded-lg p-4">
          <div class="flex items-start">
            <.icon name="hero-envelope" class="w-5 h-5 text-blue-500 mt-0.5 mr-3" />
            <div>
              <p class="text-sm text-blue-800">
                <strong>Confirmation Email Sent</strong>
                <br /> We've sent a detailed confirmation email to
                <strong><%= @current_user.email %></strong>
                with your ticket details.
              </p>
            </div>
          </div>
        </div>
        <!-- Action Buttons -->
        <div class="w-full max-w-md space-y-3">
          <.button phx-click="close-order-completion" class="w-full bg-green-600 hover:bg-green-700">
            Continue
          </.button>
          <div class="text-center">
            <p class="text-sm text-zinc-500 mb-2">
              Want to bookmark this confirmation?
            </p>
            <.link
              href={~p"/orders/#{@ticket_order.id}/confirmation"}
              class="text-blue-600 hover:text-blue-500 text-sm font-medium"
            >
              View Full Order Confirmation →
            </.link>
          </div>
        </div>
      </div>
    </.modal>
    """
  end

  @impl true
  def mount(%{"id" => event_id}, _session, socket) do
    if connected?(socket) do
      Events.subscribe()
      Agendas.subscribe(event_id)
      # Subscribe to ticket events for the current user
      if socket.assigns.current_user != nil do
        require Logger

        Logger.info("Subscribing to ticket events for user",
          user_id: socket.assigns.current_user.id,
          event_id: event_id,
          topic: "tickets:user:#{socket.assigns.current_user.id}"
        )

        Ysc.Tickets.subscribe(socket.assigns.current_user.id)
      end
    end

    event = Repo.get!(Event, event_id) |> Repo.preload(:ticket_tiers)
    agendas = Agendas.list_agendas_for_event(event_id)

    # Add pricing info to the event using the same logic as events list
    event_with_pricing = add_pricing_info(event)

    # Get user's tickets for this event if user is logged in
    user_tickets =
      if socket.assigns.current_user do
        Ysc.Tickets.list_user_tickets_for_event(socket.assigns.current_user.id, event_id)
      else
        []
      end

    # Check if we're on the tickets route (live_action == :tickets)
    show_ticket_modal = socket.assigns.live_action == :tickets

    {:ok,
     socket
     |> assign(:page_title, event.title)
     |> assign(:event, event_with_pricing)
     |> assign(:agendas, agendas)
     |> assign(:active_agenda, default_active_agenda(agendas))
     |> assign(:user_tickets, user_tickets)
     |> assign(:show_ticket_modal, show_ticket_modal)
     |> assign(:show_payment_modal, false)
     |> assign(:show_free_ticket_confirmation, false)
     |> assign(:show_order_completion, false)
     |> assign(:payment_intent, nil)
     |> assign(:public_key, Application.get_env(:stripity_stripe, :public_key))
     |> assign(:ticket_order, nil)
     |> assign(:selected_tickets, %{})
     |> assign(:checkout_expired, false)
     |> assign(:show_registration_modal, false)
     |> assign(:ticket_details_form, %{})}
  end

  @impl true
  def handle_info({Ysc.Events, %Ysc.MessagePassingEvents.EventUpdated{event: event}}, socket) do
    # Add pricing info to the updated event
    event_with_pricing = add_pricing_info(event)
    {:noreply, assign(socket, :event, event_with_pricing)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaAdded{agenda: agenda}},
        socket
      ) do
    new_agendas = socket.assigns.agendas ++ [agenda]

    {:noreply,
     socket
     |> assign(:agendas, new_agendas)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaUpdated{agenda: agenda}},
        socket
      ) do
    new_agendas =
      socket.assigns.agendas
      |> Enum.map(fn
        a when a.id == agenda.id -> agenda
        a -> a
      end)

    {:noreply,
     socket
     |> assign(:agendas, new_agendas)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaDeleted{agenda: agenda}},
        socket
      ) do
    new_agendas = socket.assigns.agendas |> Enum.reject(&(&1.id == agenda.id))
    active_agenda = new_active_agenda(agenda.id, socket.assigns.active_agenda, new_agendas)

    {:noreply, socket |> assign(:agendas, new_agendas) |> assign(:active_agenda, active_agenda)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaRepositioned{agenda: agenda}},
        socket
      ) do
    agendas = Agendas.list_agendas_for_event(agenda.event_id)
    {:noreply, socket |> assign(:agendas, agendas)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaItemAdded{agenda_item: agenda_item}},
        socket
      ) do
    updated_agendas =
      socket.assigns.agendas
      |> Enum.map(fn
        agenda when agenda.id == agenda_item.agenda_id ->
          %{agenda | agenda_items: agenda.agenda_items ++ [agenda_item]}

        agenda ->
          agenda
      end)

    {:noreply,
     socket
     |> assign(:agendas, updated_agendas)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaItemDeleted{agenda_item: agenda_item}},
        socket
      ) do
    updated_agendas =
      socket.assigns.agendas
      |> Enum.map(fn
        agenda when agenda.id == agenda_item.agenda_id ->
          %{agenda | agenda_items: Enum.reject(agenda.agenda_items, &(&1.id == agenda_item.id))}

        agenda ->
          agenda
      end)

    {:noreply, socket |> assign(:agendas, updated_agendas)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas,
         %Ysc.MessagePassingEvents.AgendaItemRepositioned{agenda_item: _agenda_item}},
        socket
      ) do
    updated_agendas = Agendas.list_agendas_for_event(socket.assigns.event.id)

    {:noreply,
     socket
     |> assign(:agendas, updated_agendas)}
  end

  @impl true
  def handle_info(
        {Ysc.Agendas, %Ysc.MessagePassingEvents.AgendaItemUpdated{agenda_item: agenda_item}},
        socket
      ) do
    updated_agendas =
      socket.assigns.agendas
      |> Enum.map(fn
        agenda when agenda.id == agenda_item.agenda_id ->
          agenda
          |> Map.update!(
            :agenda_items,
            &Enum.map(&1, fn
              item when item.id == agenda_item.id -> agenda_item
              item -> item
            end)
          )

        agenda ->
          agenda
      end)

    {:noreply,
     socket
     |> assign(:agendas, updated_agendas)}
  end

  @impl true
  def handle_info(
        {Ysc.Tickets, %Ysc.MessagePassingEvents.CheckoutSessionExpired{} = event},
        socket
      ) do
    # Handle checkout session expiration
    require Logger

    Logger.info("Received CheckoutSessionExpired event in EventDetailsLive",
      user_id: socket.assigns.current_user.id,
      show_payment_modal: socket.assigns.show_payment_modal,
      current_ticket_order_id: socket.assigns.ticket_order && socket.assigns.ticket_order.id,
      expired_ticket_order_id: event.ticket_order && event.ticket_order.id,
      event_data: inspect(event, limit: :infinity)
    )

    # Show expired message if:
    # 1. We have a payment modal open, OR
    # 2. This is the same session that expired
    current_order_id = socket.assigns.ticket_order && socket.assigns.ticket_order.id
    expired_order_id = event.ticket_order && event.ticket_order.id

    if socket.assigns.show_payment_modal &&
         (current_order_id == expired_order_id || current_order_id == nil) do
      # Show expired message for the current session or if no specific session is active
      {:noreply,
       socket
       |> assign(:checkout_expired, true)
       |> assign(:payment_intent, nil)
       |> assign(:ticket_order, nil)}
    else
      # This is a different session, just clear the current state without showing expired message
      {:noreply,
       socket
       |> assign(:show_payment_modal, false)
       |> assign(:payment_intent, nil)
       |> assign(:ticket_order, nil)
       |> assign(:selected_tickets, %{})}
    end
  end

  @impl true
  def handle_info(
        {Ysc.Tickets, %Ysc.MessagePassingEvents.CheckoutSessionCancelled{} = event},
        socket
      ) do
    # Handle checkout session cancellation
    require Logger

    Logger.info("Received CheckoutSessionCancelled event in EventDetailsLive",
      user_id: socket.assigns.current_user.id,
      show_payment_modal: socket.assigns.show_payment_modal,
      current_ticket_order_id: socket.assigns.ticket_order && socket.assigns.ticket_order.id,
      cancelled_ticket_order_id: event.ticket_order && event.ticket_order.id
    )

    # Only show expired message if this is the same session that was cancelled
    if socket.assigns.ticket_order && event.ticket_order &&
         socket.assigns.ticket_order.id == event.ticket_order.id do
      {:noreply,
       socket
       |> assign(:checkout_expired, true)
       |> assign(:payment_intent, nil)
       |> assign(:ticket_order, nil)}
    else
      # This is a different session, just clear the current state without showing expired message
      {:noreply,
       socket
       |> assign(:show_payment_modal, false)
       |> assign(:payment_intent, nil)
       |> assign(:ticket_order, nil)
       |> assign(:selected_tickets, %{})}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    # Cancel any pending ticket order when the LiveView terminates
    if socket.assigns.ticket_order && socket.assigns.show_payment_modal do
      Ysc.Tickets.cancel_ticket_order(socket.assigns.ticket_order, "User left checkout")
    end
  end

  @impl true
  def handle_event("set-active-agenda", %{"id" => id}, socket) do
    {:noreply, assign(socket, :active_agenda, id)}
  end

  @impl true
  def handle_event("toggle-map", _, socket) do
    event = socket.assigns.event

    {:noreply,
     socket
     |> Phoenix.LiveView.push_event("add-marker", %{
       lat: event.latitude,
       lon: event.longitude,
       locked: true
     })
     |> Phoenix.LiveView.push_event("position", %{})
     |> Phoenix.LiveView.push_event("toggle-map-text", %{})}
  end

  @impl true
  def handle_event("login-redirect", _params, socket) do
    {:noreply, socket |> redirect(to: ~p"/users/log-in")}
  end

  @impl true
  def handle_event("open-ticket-modal", _params, socket) do
    {:noreply, socket |> push_navigate(to: ~p"/events/#{socket.assigns.event.id}/tickets")}
  end

  @impl true
  def handle_event("close-ticket-modal", _params, socket) do
    # If we're on the tickets route, navigate back to the event details page
    if socket.assigns.live_action == :tickets do
      {:noreply,
       socket
       |> push_navigate(to: ~p"/events/#{socket.assigns.event.id}")
       |> assign(:show_ticket_modal, false)
       |> assign(:selected_tickets, %{})}
    else
      {:noreply,
       socket
       |> assign(:show_ticket_modal, false)
       |> assign(:selected_tickets, %{})}
    end
  end

  @impl true
  def handle_event("close-payment-modal", _params, socket) do
    # Cancel the ticket order to release reserved tickets
    if socket.assigns.ticket_order do
      Ysc.Tickets.cancel_ticket_order(socket.assigns.ticket_order, "User cancelled checkout")
    end

    {:noreply,
     socket
     |> assign(:show_payment_modal, false)
     |> assign(:checkout_expired, false)
     |> assign(:payment_intent, nil)
     |> assign(:ticket_order, nil)}
  end

  @impl true
  def handle_event("close-registration-modal", _params, socket) do
    # Cancel the ticket order to release reserved tickets
    if socket.assigns.ticket_order do
      Ysc.Tickets.cancel_ticket_order(
        socket.assigns.ticket_order,
        "User cancelled registration"
      )
    end

    {:noreply,
     socket
     |> assign(:show_registration_modal, false)
     |> assign(:ticket_order, nil)
     |> assign(:tickets_requiring_registration, [])
     |> assign(:ticket_details_form, %{})}
  end

  @impl true
  def handle_event("submit-registration", params, socket) do
    # Extract ticket details from form params
    ticket_details_list =
      socket.assigns.tickets_requiring_registration
      |> Enum.map(fn ticket ->
        %{
          ticket_id: ticket.id,
          first_name: params["ticket_#{ticket.id}_first_name"] || "",
          last_name: params["ticket_#{ticket.id}_last_name"] || "",
          email: params["ticket_#{ticket.id}_email"] || ""
        }
      end)

    # Validate that all fields are filled
    all_valid =
      ticket_details_list
      |> Enum.all?(fn detail ->
        detail.first_name != "" &&
          detail.last_name != "" &&
          detail.email != ""
      end)

    if all_valid do
      # Save ticket details
      case Ysc.Events.create_ticket_details(ticket_details_list) do
        {:ok, _ticket_details} ->
          # Proceed to payment or free confirmation
          proceed_to_payment_or_free(
            socket
            |> assign(:show_registration_modal, false)
            |> assign(:tickets_requiring_registration, [])
            |> assign(:ticket_details_form, %{}),
            socket.assigns.ticket_order
          )

        {:error, _reason} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             "Failed to save registration details. Please try again."
           )}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Please fill in all required fields for each ticket.")}
    end
  end

  @impl true
  def handle_event("close-free-ticket-confirmation", _params, socket) do
    # Cancel the ticket order to release reserved tickets
    if socket.assigns.ticket_order do
      Ysc.Tickets.cancel_ticket_order(
        socket.assigns.ticket_order,
        "User cancelled free ticket confirmation"
      )
    end

    {:noreply,
     socket
     |> assign(:show_free_ticket_confirmation, false)
     |> assign(:ticket_order, nil)}
  end

  @impl true
  def handle_event("confirm-free-tickets", _params, socket) do
    # Process the free ticket order directly without payment
    case Ysc.Tickets.process_free_ticket_order(socket.assigns.ticket_order) do
      {:ok, updated_order} ->
        # Get the completed order with tickets for the completion screen
        order_with_tickets = Ysc.Tickets.get_ticket_order(updated_order.id)

        # Update user tickets for this event
        updated_user_tickets =
          Ysc.Tickets.list_user_tickets_for_event(
            socket.assigns.current_user.id,
            socket.assigns.event.id
          )

        {:noreply,
         socket
         |> assign(:show_free_ticket_confirmation, false)
         |> assign(:show_order_completion, true)
         |> assign(:ticket_order, order_with_tickets)
         |> assign(:user_tickets, updated_user_tickets)
         |> assign(:selected_tickets, %{})
         |> redirect(to: ~p"/orders/#{order_with_tickets.id}/confirmation")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to confirm free tickets: #{reason}")
         |> assign(:show_free_ticket_confirmation, false)}
    end
  end

  @impl true
  def handle_event("close-order-completion", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_order_completion, false)
     |> assign(:ticket_order, nil)}
  end

  @impl true
  def handle_event("payment-success", %{"payment_intent_id" => payment_intent_id}, socket) do
    # Process the successful payment
    case Ysc.Tickets.StripeService.process_successful_payment(payment_intent_id) do
      {:ok, completed_order} ->
        # Get the completed order with tickets for the completion screen
        order_with_tickets = Ysc.Tickets.get_ticket_order(completed_order.id)

        # Update user tickets for this event
        updated_user_tickets =
          Ysc.Tickets.list_user_tickets_for_event(
            socket.assigns.current_user.id,
            socket.assigns.event.id
          )

        {:noreply,
         socket
         |> assign(:show_payment_modal, false)
         |> assign(:show_order_completion, true)
         |> assign(:ticket_order, order_with_tickets)
         |> assign(:user_tickets, updated_user_tickets)
         |> assign(:payment_intent, nil)
         |> assign(:selected_tickets, %{})
         |> redirect(to: ~p"/orders/#{order_with_tickets.id}/confirmation")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Payment processed but there was an issue confirming your tickets. Please contact support."
         )
         |> assign(:show_payment_modal, false)}
    end
  end

  @impl true
  def handle_event("checkout-expired", _params, socket) do
    # Expire the ticket order to release reserved tickets
    if socket.assigns.ticket_order do
      Ysc.Tickets.expire_ticket_order(socket.assigns.ticket_order)
    end

    # Handle checkout expiration
    {:noreply,
     socket
     |> put_flash(
       :error,
       "Your checkout session has expired. Please select your tickets again to continue."
     )
     |> assign(:show_payment_modal, false)
     |> assign(:payment_intent, nil)
     |> assign(:ticket_order, nil)
     |> assign(:selected_tickets, %{})}
  end

  @impl true
  def handle_event("retry-checkout", _params, socket) do
    # Reset checkout state and show ticket selection modal
    {:noreply,
     socket
     |> assign(:checkout_expired, false)
     |> assign(:show_payment_modal, false)
     |> assign(:payment_intent, nil)
     |> assign(:ticket_order, nil)
     |> assign(:selected_tickets, %{})
     |> assign(:show_ticket_modal, true)}
  end

  @impl true
  def handle_event("increase-ticket-quantity", %{"tier-id" => tier_id}, socket) do
    ticket_tier = get_ticket_tier_by_id(socket.assigns.event.id, tier_id)

    # Only handle quantity changes for non-donation tiers
    if ticket_tier.type == "donation" || ticket_tier.type == :donation do
      {:noreply, socket}
    else
      current_quantity = get_ticket_quantity(socket.assigns.selected_tickets, tier_id)

      # Check if we can increase the quantity before proceeding
      if can_increase_quantity?(
           ticket_tier,
           current_quantity,
           socket.assigns.selected_tickets,
           socket.assigns.event
         ) do
        new_quantity = current_quantity + 1
        # Preserve all existing selected_tickets, only update this tier's quantity
        updated_tickets = Map.put(socket.assigns.selected_tickets, tier_id, new_quantity)
        {:noreply, assign(socket, :selected_tickets, updated_tickets)}
      else
        # Don't increase if we've reached the limit
        {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("update-donation-amount", params, socket) do
    tier_id = params["tier-id"] || params["tier_id"]

    # The JavaScript hook pushes the value using the input's name attribute
    # Try to get the value from params using the input name pattern
    # The name is "donation_amount_#{tier_id}"
    value =
      if tier_id do
        params["donation_amount_#{tier_id}"] ||
          params["donation_amount"] ||
          params["value"] ||
          params["val"] ||
          ""
      else
        # Fallback: try to find any donation_amount_* key
        params
        |> Map.keys()
        |> Enum.find(&String.starts_with?(&1, "donation_amount_"))
        |> case do
          nil -> ""
          key -> params[key] || ""
        end
      end

    # Parse the donation amount from the input string (e.g., "10.99" -> 1099 cents)
    donation_amount_cents = parse_donation_amount(value)

    updated_tickets =
      if donation_amount_cents > 0 and tier_id do
        # Add or update the donation amount in selected_tickets
        Map.put(socket.assigns.selected_tickets, tier_id, donation_amount_cents)
      else
        # Remove the donation tier from selected_tickets if amount is 0 or empty
        if tier_id,
          do: Map.delete(socket.assigns.selected_tickets, tier_id),
          else: socket.assigns.selected_tickets
      end

    {:noreply, assign(socket, :selected_tickets, updated_tickets)}
  end

  @impl true
  def handle_event("set-donation-amount", %{"tier-id" => tier_id, "amount" => amount_str}, socket) do
    # Parse the amount string to integer (amount is in cents)
    case Integer.parse(amount_str) do
      {amount_cents, _} when amount_cents > 0 ->
        # Set the donation amount in selected_tickets (amount is already in cents)
        updated_tickets = Map.put(socket.assigns.selected_tickets, tier_id, amount_cents)
        {:noreply, assign(socket, :selected_tickets, updated_tickets)}

      _ ->
        # Invalid amount, don't update
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("decrease-ticket-quantity", %{"tier-id" => tier_id}, socket) do
    current_quantity = get_ticket_quantity(socket.assigns.selected_tickets, tier_id)
    new_quantity = max(0, current_quantity - 1)

    updated_tickets =
      if new_quantity == 0 do
        Map.delete(socket.assigns.selected_tickets, tier_id)
      else
        Map.put(socket.assigns.selected_tickets, tier_id, new_quantity)
      end

    {:noreply, assign(socket, :selected_tickets, updated_tickets)}
  end

  @impl true
  def handle_event("proceed-to-checkout", _params, socket) do
    user_id = socket.assigns.current_user.id
    event_id = socket.assigns.event.id
    ticket_selections = socket.assigns.selected_tickets

    case Ysc.Tickets.create_ticket_order(user_id, event_id, ticket_selections) do
      {:ok, ticket_order} ->
        # Reload the ticket order with tickets and their tiers
        ticket_order_with_tickets = Ysc.Tickets.get_ticket_order(ticket_order.id)

        # Check if any tickets require registration
        tickets_requiring_registration =
          get_tickets_requiring_registration(ticket_order_with_tickets.tickets)

        if Enum.any?(tickets_requiring_registration) do
          # Show registration modal first
          {:noreply,
           socket
           |> assign(:show_ticket_modal, false)
           |> assign(:show_registration_modal, true)
           |> assign(:ticket_order, ticket_order_with_tickets)
           |> assign(:tickets_requiring_registration, tickets_requiring_registration)
           |> assign(
             :ticket_details_form,
             initialize_ticket_details_form(tickets_requiring_registration)
           )}
        else
          # No registration required, proceed directly to payment/free confirmation
          proceed_to_payment_or_free(socket, ticket_order_with_tickets)
        end

      {:error, :overbooked} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Sorry, the event is now at capacity or the selected tickets are no longer available."
         )
         |> assign(:show_ticket_modal, false)}

      {:error, :event_not_available} ->
        {:noreply,
         socket
         |> put_flash(:error, "This event is no longer available for ticket purchase.")
         |> assign(:show_ticket_modal, false)}

      {:error, :membership_required} ->
        {:noreply,
         socket
         |> put_flash(:error, "An active membership is required to purchase tickets.")
         |> assign(:show_ticket_modal, false)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to create ticket order. Please try again.")
         |> assign(:show_ticket_modal, false)}
    end
  end

  def format_start_date(date) do
    Timex.format!(date, "{WDfull}, {Mfull} {D}")
  end

  defp event_body(%Event{rendered_details: nil} = event),
    do: Scrubber.scrub(event.raw_details, Scrubber.BasicHTML)

  defp event_body(%Event{} = event), do: event.rendered_details

  defp default_active_agenda([]), do: nil
  defp default_active_agenda(agendas), do: hd(agendas).id

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

  defp format_start_end(start_time, end_time) do
    start_time = format_time(start_time)
    end_time = format_time(end_time)

    case {start_time, end_time} do
      {nil, nil} ->
        nil

      {nil, _} ->
        end_time

      {_, nil} ->
        Timex.format!(start_time, "{h12}:{m} {AM}")

      {start_time, end_time} ->
        "#{Timex.format!(start_time, "{h12}:{m} {AM}")} - #{Timex.format!(end_time, "{h12}:{m} {AM}")}"
    end
  end

  def date_for_add_to_cal(nil), do: nil

  def date_for_add_to_cal(dt) do
    ts = Timex.Timezone.get("America/Los_Angeles", Timex.now())
    new_date = Timex.Timezone.convert(dt, ts)

    Timex.format!(new_date, "%Y-%m-%d", :strftime)
  end

  defp get_end_time_for_calendar(event) do
    case {event.start_time, event.end_time} do
      {start_time, nil} when not is_nil(start_time) ->
        # Add 3 hours to start_time when end_time is null
        Time.add(start_time, 3 * 60 * 60, :second)

      {_start_time, end_time} ->
        # Use the actual end_time if it exists
        end_time
    end
  end

  defp get_end_date_for_calendar(event) do
    case {event.start_time, event.end_time, event.end_date} do
      {start_time, nil, _end_date} when not is_nil(start_time) ->
        # Calculate end time and check if it goes past midnight
        calculated_end_time = Time.add(start_time, 3 * 60 * 60, :second)

        # If calculated end time is earlier than start time, it means we went past midnight
        if Time.compare(calculated_end_time, start_time) == :lt do
          # Add one day to the start date
          case event.start_date do
            %DateTime{} = start_date ->
              DateTime.add(start_date, 1, :day)

            _ ->
              # If start_date is not a DateTime, try to add a day using Date
              case event.start_date do
                %Date{} = start_date ->
                  Date.add(start_date, 1)

                _ ->
                  event.start_date
              end
          end
        else
          # End time is on the same day, use start_date
          event.start_date
        end

      {_start_time, _end_time, end_date} ->
        # Use the actual end_date if it exists
        end_date
    end
  end

  defp new_active_agenda(agenda_id, active_agenda_id, new_agendas)
       when agenda_id == active_agenda_id do
    default_active_agenda(new_agendas)
  end

  defp new_active_agenda(_, active_agenda_id, _) do
    active_agenda_id
  end

  # Helper function to add pricing information to events (same logic as Events module)
  defp add_pricing_info(event) do
    ticket_tiers = Events.list_ticket_tiers_for_event(event.id)
    pricing_info = calculate_event_pricing(ticket_tiers)
    Map.put(event, :pricing_info, pricing_info)
  end

  # Calculate pricing display information for an event
  defp calculate_event_pricing([]) do
    %{display_text: "FREE", has_free_tiers: true, lowest_price: nil}
  end

  defp calculate_event_pricing(ticket_tiers) do
    # Check if there are any free tiers (handle both atom and string types)
    has_free_tiers = Enum.any?(ticket_tiers, &(&1.type == :free or &1.type == "free"))

    # Get the lowest price from paid tiers only (exclude donation tiers)
    # Filter out donation, free, and tiers with nil prices
    paid_tiers =
      Enum.filter(ticket_tiers, fn tier ->
        (tier.type == :paid or tier.type == "paid") && tier.price != nil
      end)

    case {has_free_tiers, paid_tiers} do
      {true, []} ->
        %{display_text: "FREE", has_free_tiers: true, lowest_price: nil}

      {true, _paid_tiers} ->
        # When there are both free and paid tiers, show "From $0.00"
        %{display_text: "From $0.00", has_free_tiers: true, lowest_price: nil}

      {false, []} ->
        %{display_text: "FREE", has_free_tiers: false, lowest_price: nil}

      {false, paid_tiers} ->
        lowest_price = Enum.min_by(paid_tiers, & &1.price.amount, fn -> nil end)

        # If there's only one paid tier, show the exact price instead of "From $X"
        display_text =
          if length(paid_tiers) == 1 do
            format_price(lowest_price.price)
          else
            "From #{format_price(lowest_price.price)}"
          end

        %{
          display_text: display_text,
          has_free_tiers: false,
          lowest_price: lowest_price
        }
    end
  end

  # Format price for display
  defp format_price(%Money{} = money) do
    Ysc.MoneyHelper.format_money!(money)
  end

  defp format_price(_), do: "$0.00"

  # Helper functions for ticket modal
  defp get_ticket_tiers(event_id) do
    Events.list_ticket_tiers_for_event(event_id)
    |> Enum.sort_by(fn tier ->
      # Sort by status: available tiers first, then pre-sale tiers, then sold-out/ended tiers
      available = get_available_quantity(tier)
      on_sale = tier_on_sale?(tier)
      sale_ended = tier_sale_ended?(tier)

      cond do
        # Available tiers
        on_sale and available > 0 -> {0, tier.inserted_at}
        # Pre-sale tiers
        not on_sale and not sale_ended -> {1, tier.inserted_at}
        # Sale-ended tiers
        sale_ended -> {2, tier.inserted_at}
        # Sold-out tiers
        on_sale and available == 0 -> {3, tier.inserted_at}
        # Fallback
        true -> {4, tier.inserted_at}
      end
    end)
  end

  defp get_ticket_tier_by_id(event_id, tier_id) do
    get_ticket_tiers(event_id)
    |> Enum.find(&(&1.id == tier_id))
  end

  defp get_ticket_quantity(selected_tickets, tier_id) do
    Map.get(selected_tickets, tier_id, 0)
  end

  defp get_available_quantity(ticket_tier) do
    quantity = Map.get(ticket_tier, :quantity) || Map.get(ticket_tier, "quantity")

    sold_count =
      Map.get(ticket_tier, :sold_tickets_count) || Map.get(ticket_tier, "sold_tickets_count") || 0

    case quantity do
      # Unlimited
      nil ->
        :unlimited

      # Unlimited
      0 ->
        :unlimited

      qty ->
        available = qty - sold_count
        max(0, available)
    end
  end

  defp event_at_capacity?(event) do
    # Get all ticket tiers for the event
    ticket_tiers = Events.list_ticket_tiers_for_event(event.id)

    # Filter out donation tiers - donations don't count toward "sold out" status
    non_donation_tiers =
      Enum.filter(ticket_tiers, fn tier ->
        tier_type = Map.get(tier, :type) || Map.get(tier, "type")
        tier_type != "donation" && tier_type != :donation
      end)

    # If there are no non-donation tiers, event is not sold out
    if Enum.empty?(non_donation_tiers) do
      false
    else
      # Filter out pre-sale tiers (tiers that haven't started selling yet)
      # We want to check tiers that are on sale OR have ended their sale
      relevant_tiers =
        Enum.filter(non_donation_tiers, fn tier ->
          tier_on_sale?(tier) || tier_sale_ended?(tier)
        end)

      # If there are no relevant tiers (all are pre-sale), check event capacity
      if Enum.empty?(relevant_tiers) do
        # Check event capacity if max_attendees is set
        case event.max_attendees do
          nil ->
            false

          max_attendees ->
            total_sold = Events.count_total_tickets_sold_for_event(event.id)
            total_sold >= max_attendees
        end
      else
        # Check if all relevant non-donation tiers are sold out
        all_tiers_sold_out =
          Enum.all?(relevant_tiers, fn tier ->
            available = get_available_quantity(tier)
            available == 0
          end)

        # Also check event capacity if max_attendees is set
        event_at_capacity =
          case event.max_attendees do
            nil ->
              false

            max_attendees ->
              total_sold = Events.count_total_tickets_sold_for_event(event.id)
              total_sold >= max_attendees
          end

        all_tiers_sold_out || event_at_capacity
      end
    end
  end

  defp tier_on_sale?(ticket_tier) do
    now = DateTime.utc_now()

    start_date = Map.get(ticket_tier, :start_date) || Map.get(ticket_tier, "start_date")
    end_date = Map.get(ticket_tier, :end_date) || Map.get(ticket_tier, "end_date")

    # Check if sale has started
    sale_started =
      case start_date do
        # No start date means sale has started
        nil -> true
        sd -> DateTime.compare(now, sd) != :lt
      end

    # Check if sale has ended
    sale_ended =
      case end_date do
        # No end date means sale hasn't ended
        nil -> false
        ed -> DateTime.compare(now, ed) == :gt
      end

    sale_started && !sale_ended
  end

  defp tier_sale_ended?(ticket_tier) do
    now = DateTime.utc_now()

    end_date = Map.get(ticket_tier, :end_date) || Map.get(ticket_tier, "end_date")

    case end_date do
      nil -> false
      ed -> DateTime.compare(now, ed) == :gt
    end
  end

  defp days_until_sale_starts(ticket_tier) do
    case ticket_tier.start_date do
      # No start date
      nil ->
        nil

      start_date ->
        now = DateTime.utc_now()

        if DateTime.compare(now, start_date) == :lt do
          # Convert to dates and calculate calendar day difference
          start_date_only = DateTime.to_date(start_date)
          now_date_only = DateTime.to_date(now)

          # Calculate days difference using calendar days
          diff = Date.diff(start_date_only, now_date_only)
          max(0, diff)
        else
          # Already on sale
          nil
        end
    end
  end

  defp can_increase_quantity?(ticket_tier, current_quantity, _selected_tickets, event) do
    # Can't increase if not on sale
    unless tier_on_sale?(ticket_tier) do
      false
    else
      # Use the atomic booking locker for real-time availability
      case Ysc.Tickets.BookingLocker.check_availability_with_lock(event.id) do
        {:ok, availability} ->
          tier_info = Enum.find(availability.tiers, &(&1.tier_id == ticket_tier.id))
          event_at_capacity = availability.event_capacity.at_capacity

          cond do
            event_at_capacity -> false
            tier_info.available == :unlimited -> true
            true -> current_quantity < tier_info.available
          end

        {:error, _} ->
          false
      end
    end
  end

  defp calculate_total_selected_tickets(selected_tickets) do
    selected_tickets
    |> Enum.reduce(0, fn {_tier_id, quantity}, acc -> acc + quantity end)
  end

  defp has_any_tickets_selected?(selected_tickets) do
    selected_tickets
    |> Enum.any?(fn {_tier_id, quantity} -> quantity > 0 end)
  end

  defp has_ticket_tiers?(event_id) do
    get_ticket_tiers(event_id) |> length() > 0
  end

  defp event_in_past?(event) do
    now = DateTime.utc_now()

    # Combine the date and time properly
    event_datetime =
      case {event.start_date, event.start_time} do
        {%DateTime{} = date, %Time{} = time} ->
          # Convert DateTime to NaiveDateTime, then combine with time
          naive_date = DateTime.to_naive(date)
          date_part = NaiveDateTime.to_date(naive_date)
          naive_datetime = NaiveDateTime.new!(date_part, time)
          DateTime.from_naive!(naive_datetime, "Etc/UTC")

        {date, time} when not is_nil(date) and not is_nil(time) ->
          # Handle other date/time combinations
          NaiveDateTime.new!(date, time)
          |> DateTime.from_naive!("Etc/UTC")

        _ ->
          # Fallback to just the date if time is nil
          event.start_date
      end

    DateTime.compare(now, event_datetime) == :gt
  end

  defp calculate_total_price(selected_tickets, event_id) do
    total =
      selected_tickets
      |> Enum.reduce(Money.new(0, :USD), fn {tier_id, amount_or_quantity}, acc ->
        ticket_tier = get_ticket_tier_by_id(event_id, tier_id)

        case ticket_tier.type do
          "free" ->
            acc

          "donation" ->
            # amount_or_quantity is already in cents for donations
            # Convert cents to dollars Decimal, then create Money
            dollars_decimal = Ysc.MoneyHelper.cents_to_dollars(amount_or_quantity)
            donation_amount = Money.new(:USD, dollars_decimal)

            case Money.add(acc, donation_amount) do
              {:ok, new_total} -> new_total
              {:error, _} -> acc
            end

          :donation ->
            # amount_or_quantity is already in cents for donations
            # Convert cents to dollars Decimal, then create Money
            dollars_decimal = Ysc.MoneyHelper.cents_to_dollars(amount_or_quantity)
            donation_amount = Money.new(:USD, dollars_decimal)

            case Money.add(acc, donation_amount) do
              {:ok, new_total} -> new_total
              {:error, _} -> acc
            end

          _ ->
            # Regular paid tiers: multiply price by quantity
            case Money.mult(ticket_tier.price, amount_or_quantity) do
              {:ok, tier_total} ->
                case Money.add(acc, tier_total) do
                  {:ok, new_total} -> new_total
                  {:error, _} -> acc
                end

              {:error, _} ->
                acc
            end
        end
      end)

    format_price(total)
  end

  defp group_tickets_by_tier(tickets) do
    tickets
    |> Enum.group_by(& &1.ticket_tier.name)
    |> Enum.sort_by(fn {_tier_name, tickets} -> length(tickets) end, :desc)
  end

  defp format_donation_amount(selected_tickets, tier_id) do
    case Map.get(selected_tickets, tier_id) do
      nil ->
        ""

      amount_cents when is_integer(amount_cents) ->
        # Convert cents to dollars and format
        dollars = amount_cents / 100
        :erlang.float_to_binary(dollars, [{:decimals, 2}])

      _ ->
        ""
    end
  end

  defp format_price_from_cents(cents) when is_integer(cents) do
    # Convert cents to dollars Decimal, then create Money
    dollars_decimal = Ysc.MoneyHelper.cents_to_dollars(cents)
    money = Money.new(:USD, dollars_decimal)
    format_price(money)
  end

  defp format_price_from_cents(_), do: "$0.00"

  defp parse_donation_amount(value) when is_binary(value) do
    # Handle empty strings explicitly
    trimmed = String.trim(value)

    if trimmed == "" || trimmed == "0" || trimmed == "0.00" do
      0
    else
      # Remove any non-numeric characters except decimal point
      cleaned = trimmed |> String.replace(~r/[^\d.]/, "")

      if cleaned == "" do
        0
      else
        case Decimal.parse(cleaned) do
          {decimal, _} ->
            # Convert to cents (multiply by 100)
            decimal
            |> Decimal.mult(Decimal.new(100))
            |> Decimal.to_integer()

          :error ->
            0
        end
      end
    end
  end

  defp parse_donation_amount(_), do: 0

  # Helper function to get tickets that require registration
  defp get_tickets_requiring_registration(tickets) do
    tickets
    |> Enum.filter(fn ticket ->
      ticket.ticket_tier && ticket.ticket_tier.requires_registration == true
    end)
  end

  # Initialize ticket details form with empty values for each ticket
  defp initialize_ticket_details_form(tickets) do
    tickets
    |> Enum.reduce(%{}, fn ticket, acc ->
      Map.put(acc, ticket.id, %{
        first_name: "",
        last_name: "",
        email: ""
      })
    end)
  end

  # Proceed to payment or free ticket confirmation after registration (if needed)
  defp proceed_to_payment_or_free(socket, ticket_order) do
    # Check if this is a free order (zero amount)
    if Money.zero?(ticket_order.total_amount) do
      # For free tickets, show confirmation modal instead of payment form
      {:noreply,
       socket
       |> assign(:show_ticket_modal, false)
       |> assign(:show_free_ticket_confirmation, true)
       |> assign(:ticket_order, ticket_order)}
    else
      # For paid tickets, create Stripe payment intent
      case Ysc.Tickets.StripeService.create_payment_intent(ticket_order,
             customer_id: socket.assigns.current_user.stripe_id
           ) do
        {:ok, payment_intent} ->
          # Show payment form with Stripe Elements
          {:noreply,
           socket
           |> assign(:show_ticket_modal, false)
           |> assign(:show_payment_modal, true)
           |> assign(:checkout_expired, false)
           |> assign(:payment_intent, payment_intent)
           |> assign(:ticket_order, ticket_order)}

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to create payment: #{reason}")
           |> assign(:show_ticket_modal, false)}
      end
    end
  end
end
