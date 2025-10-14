defmodule YscWeb.EventDetailsLive do
  use YscWeb, :live_view

  alias HtmlSanitizeEx.Scrubber

  alias Ysc.Events
  alias Ysc.Events.Event

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
              <p
                :if={
                  @event.start_date != nil && @event.start_date != "" && @event.state != :cancelled
                }
                class="font-semibold text-zinc-600"
              >
                <%= format_start_date(@event.start_date) %>
              </p>

              <p :if={@event.state == :cancelled} class="font-semibold text-red-600">
                // This event has been cancelled //
              </p>

              <h2 :if={@event.title != nil && @event.title != ""} class="text-4xl font-bold leading-8">
                <%= @event.title %>
              </h2>

              <p
                :if={@event.description != nil && @event.description != ""}
                class="font-semibold text-zinc-600 pt-2"
              >
                <%= @event.description %>
              </p>
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
                    |> JS.push("toggle-map")
                  }
                >
                  Show Map<.icon name="hero-chevron-down" class="ms-1 w-4 h-4" />
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
              <p class="font-semibold text-lg"><%= @event.pricing_info.display_text %></p>
              <p :if={@event.start_date != nil} class="text-sm text-zinc-600"><%= format_start_date(@event.start_date) %></p>
            </div>

            <div :if={@current_user == nil} class="w-full">
              <p class="text-sm text-red-700 px-2 py-1 bg-red-50 rounded mb-2 border border-red-100 text-center">
                <.icon name="hero-exclamation-circle" class="text-red-400 w-5 h-5 me-1 -mt-0.5" />Only members can access tickets
              </p>
            </div>

            <div :if={@current_user != nil && !@active_membership?} class="w-full">
              <p class="text-sm text-orange-700 px-2 py-1 bg-orange-50 rounded mb-2 border border-orange-100 text-center">
                <.icon name="hero-exclamation-circle" class="text-orange-400 w-5 h-5 me-1 -mt-0.5" />Active membership required to purchase tickets
              </p>
            </div>

            <%= if has_ticket_tiers?(@event.id) do %>
              <%= if is_event_in_past?(@event) do %>
                <div class="w-full text-center py-3">
                  <div class="text-red-600 mb-2">
                    <.icon name="hero-clock" class="w-8 h-8 mx-auto" />
                  </div>
                  <p class="text-red-700 font-medium text-sm">Event has ended</p>
                  <p class="text-red-600 text-xs mt-1">Tickets are no longer available</p>
                </div>
              <% else %>
                <.button :if={@current_user != nil && @active_membership?} class="w-full" phx-click="open-ticket-modal">
                  <.icon name="hero-ticket" class="me-2 -mt-0.5" />Get Tickets
                </.button>
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
    <.modal :if={@show_ticket_modal} id="ticket-modal" show on_cancel={JS.push("close-ticket-modal")} max_width="max-w-6xl">
      <:title>Select Tickets</:title>

      <div class="flex flex-col lg:flex-row gap-8 min-h-[400px]">
        <!-- Left Panel: Ticket Tiers -->
        <div class="lg:w-2/3 space-y-8">
          <div class="w-full border-b border-zinc-200 pb-4">
            <h2 class="text-2xl font-semibold"><%= @event.title %></h2>
            <p :if={@event.start_date != nil} class="text-sm text-zinc-600"><%= format_start_date(@event.start_date) %></p>
          </div>

          <div class="space-y-4 h-full lg:overflow-y-auto lg:max-h-[600px] lg:px-4">
            <%= for ticket_tier <- get_ticket_tiers(@event.id) do %>
              <% available = get_available_quantity(ticket_tier) %>
              <% is_event_at_capacity = is_event_at_capacity?(@event) %>
              <% is_sold_out = available == 0 || is_event_at_capacity %>
              <% is_on_sale = is_tier_on_sale?(ticket_tier) %>
              <% days_until_sale = days_until_sale_starts(ticket_tier) %>
              <% is_pre_sale = not is_on_sale %>
              <% has_selected_tickets = get_ticket_quantity(@selected_tickets, ticket_tier.id) > 0 %>
              <div class={[
                "border rounded-lg p-6 transition-all duration-200",
                cond do
                  is_sold_out -> "border-zinc-200 bg-zinc-50 opacity-60"
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
                    <p class="font-semibold text-xl">
                      <%= case ticket_tier.type do %>
                        <% "free" -> %>
                          Free
                        <% _ -> %>
                          <%= format_price(ticket_tier.price) %>
                      <% end %>
                    </p>
                    <p class={[
                      "text-base text-sm",
                      cond do
                        is_sold_out -> "text-red-500 font-semibold"
                        is_pre_sale -> "text-blue-500 font-semibold"
                        true -> "text-zinc-500"
                      end
                    ]}>
                      <%= cond do %>
                        <% is_pre_sale -> %>
                          Sale starts in <%= days_until_sale %> <%= if days_until_sale == 1, do: "day", else: "days" %>
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

                <div class="flex items-center justify-end mt-4">

                  <div class="flex items-center space-x-3">
                    <button
                      phx-click="decrease-ticket-quantity"
                      phx-value-tier-id={ticket_tier.id}
                      class={[
                        "w-10 h-10 rounded-full border flex items-center justify-center transition-colors",
                        if(is_sold_out or is_pre_sale or get_ticket_quantity(@selected_tickets, ticket_tier.id) == 0) do
                          "border-zinc-200 bg-zinc-100 text-zinc-400 cursor-not-allowed"
                        else
                          "border-zinc-300 hover:bg-zinc-50 text-zinc-700"
                        end
                      ]}
                      disabled={is_sold_out or is_pre_sale or get_ticket_quantity(@selected_tickets, ticket_tier.id) == 0}
                    >
                      <.icon name="hero-minus" class="w-5 h-5" />
                    </button>
                    <span class={[
                      "w-12 text-center font-medium text-lg",
                      if(is_sold_out or is_pre_sale, do: "text-zinc-400", else: "text-zinc-900")
                    ]}>
                      <%= get_ticket_quantity(@selected_tickets, ticket_tier.id) %>
                    </span>
                    <button
                      phx-click="increase-ticket-quantity"
                      phx-value-tier-id={ticket_tier.id}
                      class={[
                        "w-10 h-10 rounded-full border-2 flex items-center justify-center transition-all duration-200 font-semibold",
                        if(is_sold_out or is_pre_sale or !can_increase_quantity?(ticket_tier, get_ticket_quantity(@selected_tickets, ticket_tier.id), @selected_tickets, @event)) do
                          "border-zinc-200 bg-zinc-100 text-zinc-400 cursor-not-allowed"
                        else
                          "border-blue-700 bg-blue-700 hover:bg-blue-800 hover:border-blue-800 text-white"
                        end
                      ]}
                      disabled={is_sold_out or is_pre_sale or !can_increase_quantity?(ticket_tier, get_ticket_quantity(@selected_tickets, ticket_tier.id), @selected_tickets, @event)}
                    >
                      <.icon name="hero-plus" class="w-5 h-5" />
                    </button>
                  </div>
                </div>

                <!-- Show message for different tier states -->
                <div :if={is_pre_sale} class="mt-2">
                  <p class="text-sm text-blue-600 bg-blue-50 px-3 py-2 rounded-md border border-blue-200">
                    <.icon name="hero-clock" class="w-4 h-4 inline me-1" />
                    Sale starts <%= Timex.format!(ticket_tier.start_date, "{Mshort} {D}, {YYYY}") %>
                  </p>
                </div>

                <div :if={is_sold_out} class="mt-2">
                  <p class="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-md border border-red-200">
                    <.icon name="hero-x-circle" class="w-4 h-4 inline me-1" />
                    This ticket tier is sold out
                  </p>
                </div>

                <div :if={!is_sold_out && !is_pre_sale && available != :unlimited && get_ticket_quantity(@selected_tickets, ticket_tier.id) >= available} class="mt-2">
                  <p class="text-sm text-amber-600 bg-amber-50 px-3 py-2 rounded-md border border-amber-200">
                    <.icon name="hero-exclamation-triangle" class="w-4 h-4 inline me-1" />
                    Maximum available tickets selected
                  </p>
                </div>

                <div :if={!is_sold_out && !is_pre_sale && @event.max_attendees && calculate_total_selected_tickets(@selected_tickets) >= @event.max_attendees} class="mt-2">
                  <p class="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-md border border-red-200">
                    <.icon name="hero-users" class="w-4 h-4 inline me-1" />
                    Event capacity reached. No more tickets available.
                  </p>
                </div>

                <div :if={is_event_at_capacity} class="mt-2">
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

            <h3 class="text-xl font-semibold mb-6">Order Summary</h3>

            <div class="bg-zinc-50 rounded-lg p-6 space-y-4">
              <%= if has_any_tickets_selected?(@selected_tickets) do %>
                <%= for {tier_id, quantity} <- @selected_tickets, quantity > 0 do %>
                <% ticket_tier = get_ticket_tier_by_id(@event.id, tier_id) %>
                <div class="flex justify-between text-base">
                  <span><%= ticket_tier.name %> × <%= quantity %></span>
                  <span class="font-medium">
                    <%= case ticket_tier.type do %>
                      <% "free" -> %>
                        Free
                      <% _ -> %>
                        <%= case Money.mult(ticket_tier.price, quantity) do %>
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
                  <p class="hidden lg:block text-zinc-400 text-xs mt-1">Select tickets from the left to see your order</p>
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
    """
  end

  @impl true
  def mount(%{"id" => event_id}, _session, socket) do
    if connected?(socket) do
      Events.subscribe()
      Agendas.subscribe(event_id)
    end

    event = Events.get_event!(event_id)
    agendas = Agendas.list_agendas_for_event(event_id)

    # Add pricing info to the event using the same logic as events list
    event_with_pricing = add_pricing_info(event)

    {:ok,
     socket
     |> assign(:page_title, event.title)
     |> assign(:event, event_with_pricing)
     |> assign(:agendas, agendas)
     |> assign(:active_agenda, default_active_agenda(agendas))
     |> assign(:show_ticket_modal, false)
     |> assign(:selected_tickets, %{})}
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
     |> Phoenix.LiveView.push_event("position", %{})}
  end

  @impl true
  def handle_event("login-redirect", _params, socket) do
    {:noreply, socket |> redirect(to: ~p"/users/log-in")}
  end

  @impl true
  def handle_event("open-ticket-modal", _params, socket) do
    {:noreply, assign(socket, :show_ticket_modal, true)}
  end

  @impl true
  def handle_event("close-ticket-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_ticket_modal, false)
     |> assign(:selected_tickets, %{})}
  end

  @impl true
  def handle_event("increase-ticket-quantity", %{"tier-id" => tier_id}, socket) do
    current_quantity = get_ticket_quantity(socket.assigns.selected_tickets, tier_id)
    ticket_tier = get_ticket_tier_by_id(socket.assigns.event.id, tier_id)

    # Check if we can increase the quantity before proceeding
    if can_increase_quantity?(
         ticket_tier,
         current_quantity,
         socket.assigns.selected_tickets,
         socket.assigns.event
       ) do
      new_quantity = current_quantity + 1
      updated_tickets = Map.put(socket.assigns.selected_tickets, tier_id, new_quantity)
      {:noreply, assign(socket, :selected_tickets, updated_tickets)}
    else
      # Don't increase if we've reached the limit
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
    # TODO: Implement checkout logic
    {:noreply, socket}
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

      _ ->
        # No start_time, return nil
        nil
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

      _ ->
        # No start_time, return nil
        nil
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

    # Get the lowest price from paid tiers (handle both atom and string types)
    paid_tiers = Enum.filter(ticket_tiers, &(&1.type in [:paid, :donation, "paid", "donation"]))

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
      # Sort by status: available tiers first, then pre-sale tiers, then sold-out tiers
      available = get_available_quantity(tier)
      on_sale = is_tier_on_sale?(tier)

      cond do
        # Available tiers
        on_sale and available > 0 -> {0, tier.inserted_at}
        # Pre-sale tiers
        not on_sale -> {1, tier.inserted_at}
        # Sold-out tiers
        on_sale and available == 0 -> {2, tier.inserted_at}
        # Fallback
        true -> {3, tier.inserted_at}
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
    case ticket_tier.quantity do
      # Unlimited
      nil ->
        :unlimited

      # Unlimited
      0 ->
        :unlimited

      quantity ->
        available = quantity - (ticket_tier.sold_tickets_count || 0)
        max(0, available)
    end
  end

  defp is_event_at_capacity?(event) do
    case event.max_attendees do
      nil ->
        false

      max_attendees ->
        total_sold = Events.count_total_tickets_sold_for_event(event.id)
        total_sold >= max_attendees
    end
  end

  defp is_tier_on_sale?(ticket_tier) do
    now = DateTime.utc_now()

    case ticket_tier.start_date do
      # No start date means always on sale
      nil -> true
      start_date -> DateTime.compare(now, start_date) != :lt
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
          # Calculate days difference
          diff = DateTime.diff(start_date, now, :day)
          max(0, diff)
        else
          # Already on sale
          nil
        end
    end
  end

  defp can_increase_quantity?(ticket_tier, current_quantity, selected_tickets, event) do
    # Can't increase if not on sale
    if not is_tier_on_sale?(ticket_tier) do
      false
    else
      # Check if the event is already at capacity
      if is_event_at_capacity?(event) do
        false
      else
        # Check if we've reached the event's max_attendees limit
        if not within_event_capacity?(ticket_tier, current_quantity + 1, selected_tickets, event) do
          false
        else
          case get_available_quantity(ticket_tier) do
            :unlimited -> true
            available -> current_quantity < available
          end
        end
      end
    end
  end

  defp within_event_capacity?(ticket_tier, new_quantity, selected_tickets, event) do
    # Check max_attendees from the event
    case event.max_attendees do
      nil ->
        # No max_attendees limit set
        true

      max_attendees ->
        # Calculate total selected tickets across all tiers
        total_selected = calculate_total_selected_tickets(selected_tickets)

        # Calculate the new total if we add this quantity
        current_tier_quantity = get_ticket_quantity(selected_tickets, ticket_tier.id)
        new_total = total_selected - current_tier_quantity + new_quantity

        new_total <= max_attendees
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

  defp is_event_in_past?(event) do
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
      |> Enum.reduce(Money.new(0, :USD), fn {tier_id, quantity}, acc ->
        ticket_tier = get_ticket_tier_by_id(event_id, tier_id)

        case ticket_tier.type do
          "free" ->
            acc

          _ ->
            case Money.mult(ticket_tier.price, quantity) do
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
end
