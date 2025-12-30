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
    <div class="min-h-screen">
      <%!-- Split-Header: Event Cover Image with Floating Card --%>
      <div class="max-w-screen-xl mx-auto px-4 pt-8">
        <div class="relative mb-24 lg:mb-32">
          <%!-- Image with rounded corners and gradient overlay --%>
          <div class="rounded-2xl overflow-hidden relative">
            <.live_component
              id={"event-cover-#{@event.id}"}
              module={YscWeb.Components.Image}
              image_id={@event.image_id}
              preferred_type={:optimized}
              class="w-full h-[50vh] lg:h-[60vh] object-cover"
            />
            <%!-- Gradient overlay for better text readability --%>
            <div class="absolute inset-0 bg-gradient-to-t from-zinc-900/90 via-zinc-900/40 to-transparent pointer-events-none">
            </div>
          </div>

          <%!-- Floating Card with Title/Date/Location - Overlaps bottom of image --%>
          <div class="absolute bottom-0 left-0 right-0 transform translate-y-1/2 px-4 lg:px-8 z-10">
            <div class="bg-white rounded-xl shadow-2xl border border-zinc-100 p-6 lg:p-10">
              <div class="space-y-4">
                <p :if={@event.state == :cancelled} class="font-semibold text-red-600">
                  // This event has been cancelled //
                </p>

                <div :if={@event.state != :cancelled && event_at_capacity?(@event)}>
                  <.badge type="red">SOLD OUT</.badge>
                </div>

                <div
                  :if={
                    @event.start_date != nil && @event.start_date != "" && @event.state != :cancelled
                  }
                  class="flex items-center gap-3 mb-4"
                >
                  <p class="text-xs font-black text-blue-600 uppercase tracking-[0.2em]">
                    <%= format_start_date(@event.start_date) %>
                  </p>
                  <%= if event_selling_fast?(@event) do %>
                    <span class="h-3 w-px bg-zinc-200"></span>
                    <span class="text-[9px] font-black text-orange-600 bg-orange-50 px-2 py-0.5 rounded uppercase tracking-widest">
                      High Demand
                    </span>
                  <% end %>
                </div>

                <h1
                  :if={@event.title != nil && @event.title != ""}
                  class="text-3xl md:text-4xl lg:text-5xl font-black text-zinc-900 tracking-tighter leading-tight"
                >
                  <%= @event.title %>
                </h1>

                <p
                  :if={@event.description != nil && @event.description != ""}
                  class="text-lg text-zinc-600 font-light leading-relaxed"
                >
                  <%= @event.description %>
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Main Content Grid --%>
      <div class="max-w-screen-xl mx-auto px-4 pt-8 pb-12 lg:py-16">
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-16">
          <%!-- Left Column: Event Details (8/12 width on desktop) --%>
          <div class="lg:col-span-8 space-y-16">
            <%!-- User's Existing Tickets - Member Pass Style --%>
            <div :if={@current_user != nil && length(@user_tickets) > 0} class="mb-12 space-y-6">
              <%= for {order_id, order_tickets} <- group_tickets_by_order(@user_tickets) do %>
                <% tiers_by_name = group_tickets_by_tier(order_tickets) %>
                <% first_ticket = List.first(order_tickets) %>
                <% ticket_order = first_ticket.ticket_order %>
                <% order_label =
                  if ticket_order && ticket_order.reference_id do
                    ticket_order.reference_id
                  else
                    "Order ##{String.slice(order_id, 0, 8)}"
                  end %>
                <% purchase_date =
                  if ticket_order && ticket_order.completed_at do
                    Timex.format!(ticket_order.completed_at, "{Mshort} {D}, {YYYY}")
                  else
                    if first_ticket.inserted_at do
                      Timex.format!(first_ticket.inserted_at, "{Mshort} {D}, {YYYY}")
                    else
                      nil
                    end
                  end %>
                <div class="bg-zinc-900 rounded-xl p-10 text-white shadow-2xl relative overflow-hidden border border-white/5">
                  <div class="relative z-10">
                    <%!-- Order Label Badge --%>
                    <div class="flex items-center justify-between mb-6">
                      <div class="flex items-center gap-2">
                        <span class="px-3 py-1 bg-emerald-500/20 text-emerald-400 text-[10px] font-black uppercase tracking-widest rounded-lg border border-emerald-500/30">
                          <%= order_label %>
                        </span>
                        <%= if purchase_date do %>
                          <span class="text-[10px] text-zinc-500 uppercase tracking-widest">
                            • <%= purchase_date %>
                          </span>
                        <% end %>
                      </div>
                    </div>

                    <div class="flex flex-col md:flex-row md:items-center justify-between gap-8">
                      <div class="flex items-center gap-5">
                        <div class="w-14 h-14 bg-emerald-500/10 rounded-2xl flex items-center justify-center ring-1 ring-emerald-500/50">
                          <.icon name="hero-check-badge-solid" class="w-8 h-8 text-emerald-500" />
                        </div>
                        <div>
                          <h3 class="text-2xl font-black tracking-tight leading-none">
                            Your Tickets
                          </h3>
                          <div class="mt-2 space-y-1">
                            <%= for {tier_name, tickets} <- tiers_by_name do %>
                              <p class="text-xs text-zinc-500 uppercase tracking-widest font-bold">
                                <%= length(tickets) %>x <%= tier_name %>
                              </p>
                            <% end %>
                          </div>
                        </div>
                      </div>
                      <.link
                        navigate={~p"/orders/#{order_id}/confirmation"}
                        class="px-6 py-3 bg-white/10 hover:bg-white/20 backdrop-blur-md rounded text-xs font-black uppercase tracking-widest transition-all"
                      >
                        View Order
                      </.link>
                    </div>
                  </div>
                  <div class="absolute -right-12 -top-12 w-40 h-40 bg-emerald-500/10 blur-[80px] rounded-full">
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Meta Info Row - Magazine Style --%>
            <% has_duration = @event.start_time != nil && @event.end_time != nil %>
            <div class={[
              "grid gap-0 border border-zinc-100 rounded-xl overflow-hidden bg-white shadow-sm mb-12",
              if has_duration do
                "grid-cols-1 md:grid-cols-3"
              else
                "grid-cols-1 md:grid-cols-2"
              end
            ]}>
              <div class={[
                "p-8 border-b",
                if has_duration do
                  "md:border-b-0 md:border-r md:border-dashed border-zinc-200"
                else
                  "md:border-b-0 md:border-r md:border-dashed border-zinc-200"
                end
              ]}>
                <p class="text-xs font-black text-blue-600 uppercase tracking-[0.2em] mb-2">
                  When
                </p>
                <p class="font-black text-xl text-zinc-900 tracking-tighter leading-none">
                  <%= if @event.start_date != nil do %>
                    <%= Timex.format!(@event.start_date, "{Mshort} {D}") %>
                  <% else %>
                    TBD
                  <% end %>
                </p>
                <p class="text-sm text-zinc-500 mt-2 font-medium">
                  <%= if @event.start_time != nil do %>
                    Starts at <%= case format_time(@event.start_time) do
                      %Time{} = time -> Timex.format!(time, "{h12}:{m} {AM}")
                      _ -> ""
                    end %>
                  <% else %>
                    Time TBD
                  <% end %>
                </p>
                <%= if !event_in_past?(@event) && @event.state != :cancelled do %>
                  <div class="mt-3 inline-flex items-center gap-2 bg-blue-50 px-2 py-1 rounded-full">
                    <span class="w-1.5 h-1.5 rounded-full bg-blue-500 animate-pulse"></span>
                    <span class="text-[10px] font-black text-blue-600 uppercase tracking-widest">
                      Upcoming
                    </span>
                  </div>
                <% end %>
              </div>
              <div class={[
                "p-8 border-b",
                if has_duration do
                  "md:border-b-0 md:border-r md:border-dashed border-zinc-200"
                else
                  "md:border-b-0"
                end
              ]}>
                <p class="text-xs font-black text-blue-600 uppercase tracking-[0.2em] mb-2">
                  Where
                </p>
                <p class="font-black text-xl text-zinc-900 tracking-tighter leading-none">
                  <%= if @event.location_name != nil && @event.location_name != "" do %>
                    <%= @event.location_name %>
                  <% else %>
                    TBD
                  <% end %>
                </p>
                <p class="text-sm text-zinc-500 mt-2 font-medium">
                  <%= if @event.address != nil && @event.address != "" do %>
                    <%= @event.address %>
                  <% else %>
                    Location TBD
                  <% end %>
                </p>
              </div>
              <%= if has_duration do %>
                <div class="p-8 bg-zinc-50/30">
                  <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.2em] mb-2">
                    Duration
                  </p>
                  <p class="font-black text-xl text-zinc-900 tracking-tighter leading-none">
                    <%= case {format_time(@event.start_time), format_time(@event.end_time)} do
                      {%Time{} = start_time, %Time{} = end_time} ->
                        duration_minutes = Time.diff(end_time, start_time, :minute)
                        hours = div(duration_minutes, 60)
                        minutes = rem(duration_minutes, 60)

                        cond do
                          hours > 0 && minutes > 0 -> "#{hours}h #{minutes}m"
                          hours > 0 -> "#{hours} Hour#{if hours > 1, do: "s", else: ""}"
                          minutes > 0 -> "#{minutes} Minute#{if minutes > 1, do: "s", else: ""}"
                          true -> "TBD"
                        end

                      _ ->
                        "TBD"
                    end %>
                  </p>
                </div>
              <% end %>
            </div>

            <%!-- Location Details --%>
            <div
              :if={
                (@event.location_name != "" && @event.location_name != nil) ||
                  (@event.address != nil && @event.address != "")
              }
              class="space-y-4"
            >
              <div class="flex items-start gap-2">
                <.icon name="hero-map-pin" class="w-5 h-5 text-zinc-500 mt-1" />
                <div>
                  <p
                    :if={@event.location_name != nil && @event.location_name != ""}
                    class="font-semibold text-zinc-900"
                  >
                    <%= @event.location_name %>
                  </p>
                  <p :if={@event.address != nil && @event.address != ""} class="text-zinc-600">
                    <%= @event.address %>
                  </p>
                </div>
              </div>

              <div
                :if={
                  @event.latitude != nil && @event.longitude != nil && @event.latitude != "" &&
                    @event.longitude != ""
                }
                class="space-y-4"
              >
                <button
                  class="transition duration-200 ease-in-out hover:text-blue-800 text-blue-600 font-semibold"
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

                <div
                  id="event-map"
                  class="hidden bg-zinc-50 rounded-2xl border border-zinc-200 overflow-hidden"
                >
                  <.live_component
                    id={"#{@event.id}-map"}
                    module={YscWeb.Components.MapComponent}
                    event_id={@event.id}
                    latitude={@event.latitude}
                    longitude={@event.longitude}
                    locked={true}
                    class="max-w-screen-lg"
                  />

                  <div class="p-3">
                    <YscWeb.Components.MapNavigationButtons.map_navigation_buttons
                      latitude={@event.latitude}
                      longitude={@event.longitude}
                    />
                  </div>
                </div>
              </div>
            </div>

            <%!-- Agenda --%>
            <section :if={length(@agendas) > 0} class="space-y-6">
              <h3 class="text-2xl font-black text-zinc-900 tracking-tight mb-12 flex items-center gap-3">
                <span class="w-8 h-px bg-zinc-200"></span> Agenda
              </h3>

              <div :if={length(@agendas) > 1} class="py-2 mb-8">
                <ul class="flex flex-wrap gap-2 text-sm font-medium text-zinc-600">
                  <%= for agenda <- @agendas do %>
                    <li id={"agenda-selector-#{agenda.id}"}>
                      <button
                        phx-click="set-active-agenda"
                        phx-value-id={agenda.id}
                        class={[
                          "inline-flex items-center px-4 py-2 rounded-lg transition-colors",
                          agenda.id == @active_agenda && "text-white bg-blue-600",
                          agenda.id != @active_agenda &&
                            "text-zinc-600 bg-zinc-100 hover:bg-zinc-200 hover:text-zinc-800"
                        ]}
                      >
                        <%= agenda.title %>
                      </button>
                    </li>
                  <% end %>
                </ul>
              </div>

              <%= for agenda <- @agendas do %>
                <div :if={agenda.id == @active_agenda} class="relative pl-8 space-y-12">
                  <%!-- Vertical Timeline Line --%>
                  <div class="absolute left-3 top-2 bottom-2 w-px bg-zinc-100"></div>

                  <%= for agenda_item <- agenda.agenda_items do %>
                    <% is_current = agenda_item_current?(agenda_item, @event) %>
                    <div class="relative group">
                      <div class={[
                        "absolute -left-[25px] w-4 h-4 rounded-full border-4 border-white transition-all shadow-sm z-10 mt-1.5",
                        if is_current do
                          "bg-blue-600 animate-pulse"
                        else
                          "bg-zinc-200 group-hover:bg-blue-600 group-hover:scale-125"
                        end
                      ]}>
                      </div>
                      <div class="flex flex-col md:flex-row md:items-baseline gap-2 md:gap-8">
                        <div class="w-36 flex-shrink-0">
                          <span class="text-xs font-black text-blue-600 bg-blue-50 px-2.5 py-1 rounded-lg uppercase tracking-widest whitespace-nowrap group-hover:bg-blue-600 group-hover:text-white transition-colors">
                            <%= format_start_end(agenda_item.start_time, agenda_item.end_time) %>
                          </span>
                        </div>
                        <div class="flex-1 min-w-0">
                          <h4 class="text-lg font-black text-zinc-900 tracking-tight leading-none group-hover:text-blue-600 transition-colors">
                            <%= agenda_item.title %>
                          </h4>
                          <p
                            :if={agenda_item.description != nil}
                            class="text-sm text-zinc-500 font-light mt-2 leading-relaxed"
                          >
                            <%= agenda_item.description %>
                          </p>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </section>

            <%!-- Details --%>
            <section class="space-y-6">
              <h3 class="text-2xl font-black text-zinc-900 tracking-tight mb-6 flex items-center gap-3">
                <span class="w-8 h-px bg-zinc-200"></span> Details
              </h3>
              <article class="prose prose-zinc prose-lg max-w-none text-zinc-600 font-light leading-relaxed">
                <div id="article-body" class="post-render">
                  <%= raw(event_body(@event)) %>
                </div>
              </article>
            </section>
          </div>

          <%!-- Right Column: Sticky Ticket Sidebar (4/12 width on desktop) --%>
          <aside class="lg:col-span-4">
            <%!-- Spacer for mobile bottom bar --%>
            <div class="h-36 lg:hidden"></div>

            <%!-- Desktop: Sticky sidebar --%>
            <div :if={@event.state != :cancelled} class="hidden lg:block sticky top-24 space-y-8">
              <div class="bg-white rounded-xl shadow-2xl border border-zinc-100 overflow-hidden">
                <%= if event_in_past?(@event) do %>
                  <div class="p-8 text-center bg-zinc-50/50">
                    <div class="text-red-500 mb-4">
                      <.icon name="hero-clock" class="w-10 h-10 mx-auto" />
                    </div>
                    <p class="text-red-700 font-semibold">Event has ended</p>
                    <p class="text-red-500 text-sm mt-1">Tickets are no longer available</p>
                  </div>
                <% else %>
                  <div class="p-8 text-center bg-zinc-50/50 shadow-[inset_0_-10px_20px_-15px_rgba(0,0,0,0.1)]">
                    <p class="text-xs font-black text-zinc-400 uppercase tracking-[0.3em] mb-2">
                      Admission
                    </p>
                    <p class={[
                      "text-4xl font-black text-zinc-900 tracking-tighter",
                      if event_at_capacity?(@event) do
                        "line-through"
                      else
                        ""
                      end
                    ]}>
                      <%= @event.pricing_info.display_text %>
                    </p>
                    <p :if={@event.start_date != nil} class="text-sm text-zinc-500 mt-2">
                      <%= format_start_date(@event.start_date) %>
                    </p>
                  </div>
                <% end %>

                <%= if event_in_past?(@event) do %>
                  <!-- No additional content for past events -->
                <% else %>
                  <%!-- Ticket Perforation Line with Notch Cutouts --%>
                  <div class="relative h-px border-t-2 border-dashed border-zinc-200 mx-4">
                    <div class="absolute -left-11 -top-3 w-6 h-6 bg-white rounded-full border-r border-zinc-100 shadow-inner">
                    </div>
                    <div class="absolute -right-11 -top-3 w-6 h-6 bg-white rounded-full border-l border-zinc-100 shadow-inner">
                    </div>
                  </div>

                  <div class="p-8 space-y-6 shadow-[inset_0_10px_20px_-15px_rgba(0,0,0,0.05)]">
                    <%= if event_selling_fast?(@event) && !event_at_capacity?(@event) do %>
                      <% available_capacity = get_event_available_capacity(@event.id) %>
                      <% sold_percentage = get_event_sold_percentage(@event) %>
                      <div class="p-4 bg-orange-50 rounded-xl border border-orange-100 space-y-3">
                        <div class="flex items-center gap-3">
                          <div class="flex-shrink-0 w-8 h-8 bg-orange-500 rounded-full flex items-center justify-center">
                            <.icon name="hero-fire-solid" class="w-4 h-4 text-white" />
                          </div>
                          <p class="text-[11px] font-black text-orange-800 uppercase tracking-tight">
                            Demand is High
                          </p>
                        </div>
                        <%= if sold_percentage != nil do %>
                          <div class="space-y-2">
                            <div class="flex justify-between items-end">
                              <p class="text-[10px] font-black text-orange-600 uppercase tracking-widest">
                                Limited Availability
                              </p>
                              <p class="text-[10px] font-mono text-zinc-400">
                                <%= sold_percentage %>% Booked
                              </p>
                            </div>
                            <div class="w-full bg-zinc-100 h-1.5 rounded-full overflow-hidden">
                              <div
                                class="bg-orange-500 h-full transition-all duration-1000 animate-pulse"
                                style={"width: #{sold_percentage}%"}
                              >
                              </div>
                            </div>
                          </div>
                        <% else %>
                          <p class="text-[11px] text-orange-700 font-medium">
                            <%= if available_capacity != :unlimited && available_capacity <= 10 do
                              "Less than #{available_capacity} spot#{if available_capacity == 1, do: "", else: "s"} remaining"
                            else
                              "Going Fast"
                            end %>
                          </p>
                        <% end %>
                      </div>
                    <% end %>

                    <div class="space-y-3">
                      <%= if has_ticket_tiers?(@event.id) do %>
                        <% available_capacity = get_event_available_capacity(@event.id) %>
                        <div
                          :if={available_capacity != :unlimited && !event_at_capacity?(@event)}
                          class="flex items-center gap-3 text-sm text-zinc-600 font-medium"
                        >
                          <.icon name="hero-users" class="w-4 h-4 text-blue-500" />
                          <%= available_capacity %> Spots Available
                        </div>
                        <div
                          :if={@active_membership?}
                          class="flex items-center gap-3 text-sm text-zinc-600 font-medium"
                        >
                          <.icon name="hero-check-badge" class="w-4 h-4 text-blue-500" />
                          Member Exclusive
                        </div>
                      <% end %>
                    </div>

                    <div
                      :if={@current_user == nil && has_ticket_tiers?(@event.id)}
                      class="w-full space-y-4"
                    >
                      <div class="text-sm text-orange-700 px-3 py-2 bg-orange-50 rounded-lg border border-orange-200 text-center">
                        <.icon
                          name="hero-exclamation-circle"
                          class="text-orange-500 w-5 h-5 me-1 -mt-0.5"
                        /> You need to be signed in and have an active membership to purchase tickets
                      </div>
                      <.button
                        class="w-full py-4 bg-zinc-900 text-white font-black text-sm uppercase tracking-widest rounded-2xl hover:bg-blue-600 transition-all shadow-xl shadow-zinc-200 active:scale-95"
                        phx-click={
                          JS.navigate(~p"/users/log-in?redirect_to=#{~p"/events/#{@event.id}"}")
                        }
                      >
                        Sign In to Continue
                      </.button>
                    </div>

                    <div
                      :if={
                        @current_user != nil && !@active_membership? && has_ticket_tiers?(@event.id)
                      }
                      class="w-full"
                    >
                      <div class="text-sm text-orange-700 px-3 py-2 bg-orange-50 rounded-lg border border-orange-200 text-center">
                        <.icon
                          name="hero-exclamation-circle"
                          class="text-orange-500 w-5 h-5 me-1 -mt-0.5"
                        /> Active membership required to purchase tickets
                      </div>
                    </div>

                    <%= if has_ticket_tiers?(@event.id) do %>
                      <%= if event_at_capacity?(@event) do %>
                        <div class="w-full">
                          <.tooltip tooltip_text="This event is sold out">
                            <.button
                              :if={@current_user != nil && @active_membership?}
                              class="w-full py-4 uppercase tracking-widest"
                              disabled
                            >
                              <.icon name="hero-ticket" class="me-2 -mt-0.5" />Sold Out
                            </.button>
                          </.tooltip>
                        </div>
                      <% else %>
                        <.button
                          :if={@current_user != nil && @active_membership?}
                          class="w-full py-4 uppercase tracking-widest"
                          phx-click="open-ticket-modal"
                        >
                          <.icon name="hero-ticket" class="me-2 -mt-0.5" />Claim Your Spot
                        </.button>
                      <% end %>
                    <% else %>
                      <div class="w-full text-center py-2">
                        <p class="font-bold text-green-700 text-sm">No registration required</p>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>

              <%!-- Add to Calendar --%>
              <div
                :if={!event_in_past?(@event)}
                class="p-6 rounded-xl border border-zinc-100 flex items-center justify-between"
              >
                <span class="text-sm font-bold text-zinc-900">Don't forget.</span>
                <add-to-calendar-button
                  name={@event.title}
                  startDate={date_for_add_to_cal(@event.start_date)}
                  {if get_end_date_for_calendar(@event), do: [endDate: date_for_add_to_cal(get_end_date_for_calendar(@event))], else: []}
                  options="'Apple','Google','iCal','Outlook.com','Yahoo'"
                  startTime={@event.start_time}
                  {if get_end_time_for_calendar(@event), do: [endTime: get_end_time_for_calendar(@event)], else: []}
                  timeZone="America/Los_Angeles"
                  location={@event.location_name}
                  size="4"
                  lightMode="bodyScheme"
                >
                </add-to-calendar-button>
              </div>
            </div>

            <%!-- Mobile: Fixed bottom bar --%>
            <div :if={@event.state != :cancelled} class="lg:hidden fixed bottom-0 left-0 right-0 z-50">
              <div class="h-8 bg-gradient-to-t from-white to-transparent"></div>

              <div class="bg-white/95 backdrop-blur-md border-t border-zinc-100 px-6 py-5 shadow-[0_-10px_40px_-15px_rgba(0,0,0,0.1)]">
                <div class="max-w-screen-md mx-auto flex items-center justify-between gap-6">
                  <%= if event_in_past?(@event) do %>
                    <div class="flex-1 text-center">
                      <div class="text-red-700 font-black text-base">
                        Event Ended
                      </div>
                      <div class="text-red-500 text-xs mt-1">
                        Tickets are no longer available
                      </div>
                    </div>
                  <% else %>
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-2 mb-0.5">
                        <p class={[
                          "font-black text-2xl text-zinc-900 tracking-tighter leading-none",
                          if event_at_capacity?(@event) do
                            "line-through"
                          else
                            ""
                          end
                        ]}>
                          <%= @event.pricing_info.display_text %>
                        </p>
                        <%= if event_selling_fast?(@event) && !event_at_capacity?(@event) do %>
                          <span class="text-[9px] font-black text-orange-600 uppercase tracking-widest bg-orange-50 px-1.5 py-0.5 rounded">
                            Going Fast
                          </span>
                        <% else %>
                          <%= if event_live?(@event) do %>
                            <span class="text-[9px] font-black text-blue-600 uppercase tracking-widest bg-blue-50 px-1.5 py-0.5 rounded">
                              Live
                            </span>
                          <% end %>
                        <% end %>
                      </div>
                      <p
                        :if={@event.start_date != nil}
                        class="text-[10px] font-bold text-zinc-400 uppercase tracking-widest truncate"
                      >
                        <%= format_start_date(@event.start_date) %>
                        <%= if @event.start_time != nil do %>
                          • <%= case format_time(@event.start_time) do
                            %Time{} = time -> Timex.format!(time, "{h12}:{m} {AM}")
                            _ -> ""
                          end %>
                        <% end %>
                      </p>
                    </div>
                  <% end %>

                  <%= if event_in_past?(@event) do %>
                    <!-- No action button for past events -->
                  <% else %>
                    <%= if @current_user == nil && has_ticket_tiers?(@event.id) do %>
                      <.button
                        class="flex-shrink-0 px-8 py-3.5 uppercase tracking-widest"
                        phx-click={
                          JS.navigate(~p"/users/log-in?redirect_to=#{~p"/events/#{@event.id}"}")
                        }
                      >
                        <.icon name="hero-ticket" class="w-5 h-5 me-2 -mt-0.5" />Sign In
                      </.button>
                    <% else %>
                      <%= if has_ticket_tiers?(@event.id) do %>
                        <%= if event_at_capacity?(@event) do %>
                          <div class="text-red-700 font-black text-sm text-center">
                            Sold Out
                          </div>
                        <% else %>
                          <%= if @active_membership? do %>
                            <.button
                              class="flex-shrink-0 px-8 py-3.5 uppercase tracking-widest"
                              phx-click="open-ticket-modal"
                            >
                              <.icon name="hero-ticket" class="w-5 h-5 me-2 -mt-0.5" />Get Tickets
                            </.button>
                          <% else %>
                            <div class="text-orange-700 font-black text-sm text-center">
                              Membership Required
                            </div>
                          <% end %>
                        <% end %>
                      <% else %>
                        <span class="text-xs font-black text-green-700 uppercase tracking-widest">
                          No registration required
                        </span>
                      <% end %>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>
          </aside>
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
                      id={"tier-availability-#{ticket_tier.id}"}
                      class={[
                        "text-base text-sm transition-colors duration-200",
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
                        <div class="flex items-center border border-zinc-300 rounded-lg px-3 py-1 flex-1 sm:flex-initial bg-white">
                          <span class="text-zinc-800">$</span>
                          <input
                            type="text"
                            id={"donation-amount-#{ticket_tier.id}"}
                            name={"donation_amount_#{ticket_tier.id}"}
                            phx-hook="MoneyInput"
                            data-tier-id={ticket_tier.id}
                            value={format_donation_amount(@selected_tickets, ticket_tier.id)}
                            placeholder="0.00"
                            disabled={false}
                            class="w-full sm:w-32 border-0 focus:ring-0 focus:outline-none font-medium text-zinc-900"
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

                <% available_capacity = get_event_available_capacity(@event.id) %>
                <div
                  :if={
                    !is_donation && !is_sold_out && !is_pre_sale && !is_sale_ended &&
                      @event.max_attendees &&
                      available_capacity != :unlimited &&
                      calculate_total_selected_tickets(@selected_tickets, @event.id) >=
                        available_capacity
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
                preferred_type={:optimized}
              />
            </div>

            <div>
              <h2 class="text-lg font-semibold mb-6 hidden lg:block"><%= @event.title %></h2>
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
                  <p class="hidden lg:block text-zinc-400 text-sm mt-1">
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

              <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
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
                        <%= get_donation_amount_for_single_ticket(ticket) %>
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
    case Repo.get(Event, event_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Event not found")
         |> redirect(to: ~p"/events")}

      event ->
        event = Repo.preload(event, :ticket_tiers)

        if connected?(socket) do
          Events.subscribe()
          Agendas.subscribe(event_id)
          # Subscribe to event-level ticket updates for real-time availability
          Ysc.Tickets.subscribe_event(event_id)
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

        agendas = Agendas.list_agendas_for_event(event_id)

        # Add pricing info to the event using the same logic as events list
        event_with_pricing = add_pricing_info(event)

        # Get user's tickets for this event if user is signed in
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
         |> assign(:ticket_details_form, %{})
         |> assign(:load_radar, true)
         |> assign(:load_stripe, true)
         |> assign(:load_calendar, true)}
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    # Parse query parameters from URI
    query_params = parse_query_params(uri)

    # Check for resume_order query parameter
    resume_order_id = query_params["resume_order"] || query_params[:resume_order]

    socket =
      if resume_order_id && socket.assigns.current_user do
        restore_checkout_state(socket, resume_order_id, socket.assigns.event.id)
      else
        socket
      end

    {:noreply, socket}
  end

  # Helper to parse query parameters from URI
  defp parse_query_params(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{query: nil} -> %{}
      %URI{query: query} -> URI.decode_query(query)
      _ -> %{}
    end
  end

  defp parse_query_params(_), do: %{}

  # Restore checkout state from a pending order
  defp restore_checkout_state(socket, order_id, event_id) do
    case Ysc.Tickets.get_ticket_order(order_id) do
      nil ->
        socket
        |> put_flash(:error, "Order not found")

      ticket_order ->
        # Verify the order belongs to the current user and event
        if ticket_order.user_id == socket.assigns.current_user.id &&
             ticket_order.event_id == event_id &&
             ticket_order.status == :pending do
          # Check if order has expired
          if DateTime.compare(DateTime.utc_now(), ticket_order.expires_at) == :gt do
            socket
            |> put_flash(:error, "This order has expired. Please create a new order.")
          else
            # Restore the ticket order and payment intent
            restore_payment_state(socket, ticket_order)
          end
        else
          socket
          |> put_flash(:error, "Cannot resume this order")
        end
    end
  end

  # Restore payment state (payment intent or free ticket confirmation)
  defp restore_payment_state(socket, ticket_order) do
    # Reload ticket order with tickets and tiers
    ticket_order = Ysc.Tickets.get_ticket_order(ticket_order.id)

    # Reconstruct selected_tickets map from the ticket order
    selected_tickets = build_selected_tickets_from_order(ticket_order)

    # Check if any tickets require registration
    tickets_requiring_registration =
      get_tickets_requiring_registration(ticket_order.tickets)

    socket = socket |> assign(:selected_tickets, selected_tickets)

    if Enum.any?(tickets_requiring_registration) do
      # Show registration modal first
      socket
      |> assign(:show_ticket_modal, false)
      |> assign(:show_registration_modal, true)
      |> assign(:ticket_order, ticket_order)
      |> assign(:tickets_requiring_registration, tickets_requiring_registration)
      |> assign(
        :ticket_details_form,
        initialize_ticket_details_form(tickets_requiring_registration)
      )
    else
      # No registration required, proceed directly to payment/free confirmation
      if Money.zero?(ticket_order.total_amount) do
        # For free tickets, show confirmation modal
        socket
        |> assign(:show_ticket_modal, false)
        |> assign(:show_free_ticket_confirmation, true)
        |> assign(:ticket_order, ticket_order)
      else
        # For paid tickets, retrieve or create payment intent
        case retrieve_or_create_payment_intent(ticket_order, socket.assigns.current_user) do
          {:ok, payment_intent} ->
            socket
            |> assign(:show_ticket_modal, false)
            |> assign(:show_payment_modal, true)
            |> assign(:checkout_expired, false)
            |> assign(:payment_intent, payment_intent)
            |> assign(:ticket_order, ticket_order)

          {:error, reason} ->
            socket
            |> put_flash(:error, "Failed to restore payment: #{reason}")
        end
      end
    end
  end

  # Convert Money struct to cents (integer)
  defp money_to_cents(%Money{amount: amount, currency: :USD}) do
    # Use Decimal for precise conversion to avoid floating-point errors
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(%Money{amount: amount, currency: _currency}) do
    # For other currencies, use same conversion
    amount
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp money_to_cents(_) do
    # Fallback for invalid money values
    0
  end

  # Build selected_tickets map from a ticket order
  # For regular tickets: tier_id => quantity
  # For donation tickets: tier_id => amount_cents (total donation amount in cents)
  defp build_selected_tickets_from_order(ticket_order) do
    if ticket_order.tickets && length(ticket_order.tickets) > 0 do
      # Group tickets by tier_id
      tickets_by_tier =
        ticket_order.tickets
        |> Enum.group_by(& &1.ticket_tier_id)

      # Build selected_tickets map
      tickets_by_tier
      |> Enum.reduce(%{}, fn {tier_id, tickets}, acc ->
        first_ticket = List.first(tickets)
        tier = first_ticket.ticket_tier
        quantity = length(tickets)

        # Check if this is a donation tier
        is_donation = tier.type == "donation" || tier.type == :donation

        if is_donation do
          # For donations, calculate the total donation amount for this tier
          # The donation amount is stored in the ticket_order.total_amount
          # We need to calculate how much of the total is for this specific donation tier
          {_event_amount, donation_amount} =
            Ysc.Tickets.calculate_event_and_donation_amounts(ticket_order)

          # Count all donation tickets in the order
          donation_tickets_count =
            ticket_order.tickets
            |> Enum.count(fn t ->
              t.ticket_tier.type == "donation" || t.ticket_tier.type == :donation
            end)

          # Calculate donation amount per ticket, then multiply by quantity for this tier
          if donation_tickets_count > 0 do
            case Money.div(donation_amount, donation_tickets_count) do
              {:ok, amount_per_ticket} ->
                # Multiply by quantity for this tier and convert to cents
                case Money.mult(amount_per_ticket, quantity) do
                  {:ok, tier_donation_total} ->
                    # Convert Money to cents
                    amount_cents = money_to_cents(tier_donation_total)
                    Map.put(acc, tier_id, amount_cents)

                  _ ->
                    acc
                end

              _ ->
                acc
            end
          else
            acc
          end
        else
          # For regular tickets, just store the quantity
          Map.put(acc, tier_id, quantity)
        end
      end)
    else
      %{}
    end
  end

  # Retrieve existing payment intent or create a new one
  defp retrieve_or_create_payment_intent(ticket_order, user) do
    if ticket_order.payment_intent_id do
      # Try to retrieve existing payment intent
      case Stripe.PaymentIntent.retrieve(ticket_order.payment_intent_id, %{}) do
        {:ok, payment_intent} ->
          # Check if payment intent is still valid (not succeeded or canceled)
          if payment_intent.status in [
               "requires_payment_method",
               "requires_confirmation",
               "requires_action"
             ] do
            {:ok, payment_intent}
          else
            # Payment intent is in a final state, create a new one
            Ysc.Tickets.StripeService.create_payment_intent(ticket_order,
              customer_id: user.stripe_id
            )
          end

        {:error, _} ->
          # Payment intent not found, create a new one
          Ysc.Tickets.StripeService.create_payment_intent(ticket_order,
            customer_id: user.stripe_id
          )
      end
    else
      # No payment intent exists, create a new one
      Ysc.Tickets.StripeService.create_payment_intent(ticket_order,
        customer_id: user.stripe_id
      )
    end
  end

  @impl true
  def handle_info({Ysc.Events, %Ysc.MessagePassingEvents.EventUpdated{event: event}}, socket) do
    # Add pricing info to the updated event
    # Ensure ticket_tiers is preloaded in case it wasn't included in the event update
    event = Repo.preload(event, :ticket_tiers)
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
  def handle_info(
        {Ysc.Tickets, %Ysc.MessagePassingEvents.TicketAvailabilityUpdated{event_id: event_id}},
        socket
      ) do
    # Handle ticket availability updates - refresh the event to get updated availability counts
    # Only process if this is for the current event
    if socket.assigns.event.id == event_id do
      # Reload the event and recalculate pricing info with fresh ticket tier data
      # This will trigger a re-render with updated availability counts
      event = Repo.get(Event, event_id) |> Repo.preload(:ticket_tiers)
      event_with_pricing = add_pricing_info(event)

      # Trigger animation on all tier availability elements
      {:noreply,
       socket
       |> assign(:event, event_with_pricing)
       |> push_event("animate-availability-update", %{})}
    else
      {:noreply, socket}
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
         |> redirect(to: ~p"/orders/#{order_with_tickets.id}/confirmation?confetti=true")}

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
         |> redirect(to: ~p"/orders/#{order_with_tickets.id}/confirmation?confetti=true")}

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

      {:error, :event_capacity_exceeded} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Sorry, the event has reached its maximum capacity. The selected tickets are no longer available."
         )
         |> assign(:show_ticket_modal, false)}

      {:error, :stale_inventory} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "The ticket availability changed while you were booking. Please refresh and try again."
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
    Timex.format!(dt, "%Y-%m-%d", :strftime)
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

  defp can_increase_quantity?(ticket_tier, current_quantity, selected_tickets, event) do
    # Can't increase if not on sale
    if !tier_on_sale?(ticket_tier) do
      false
    else
      # Donations don't count toward capacity
      if ticket_tier.type == "donation" || ticket_tier.type == :donation do
        true
      else
        # Use the atomic booking locker for real-time availability
        case Ysc.Tickets.BookingLocker.check_availability_with_lock(event.id) do
          {:ok, availability} ->
            tier_info = Enum.find(availability.tiers, &(&1.tier_id == ticket_tier.id))
            event_capacity = availability.event_capacity

            # Check tier availability first
            tier_available =
              cond do
                tier_info.available == :unlimited -> true
                true -> current_quantity < tier_info.available
              end

            # Check event global capacity
            event_available =
              case event_capacity.available do
                :unlimited ->
                  true

                available ->
                  # Calculate total selected tickets (excluding donations)
                  total_selected = calculate_total_selected_tickets(selected_tickets, event.id)
                  # Check if adding one more ticket would exceed capacity
                  total_selected + 1 <= available
              end

            tier_available && event_available

          {:error, _} ->
            false
        end
      end
    end
  end

  defp calculate_total_selected_tickets(selected_tickets, event_id) do
    selected_tickets
    |> Enum.reduce(0, fn {tier_id, quantity}, acc ->
      # Only count non-donation tiers towards event capacity
      ticket_tier = get_ticket_tier_by_id(event_id, tier_id)

      if ticket_tier && (ticket_tier.type != "donation" && ticket_tier.type != :donation) do
        acc + quantity
      else
        acc
      end
    end)
  end

  defp get_event_available_capacity(event_id) do
    case Ysc.Tickets.BookingLocker.check_availability_with_lock(event_id) do
      {:ok, availability} ->
        availability.event_capacity.available

      {:error, _} ->
        :unlimited
    end
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

  defp group_tickets_by_order(tickets) do
    tickets
    |> Enum.filter(&(&1.ticket_order_id != nil))
    |> Enum.group_by(& &1.ticket_order_id)
    |> Enum.sort_by(
      fn {_order_id, order_tickets} ->
        # Sort by the most recent ticket's inserted_at (most recent orders first)
        List.first(order_tickets).inserted_at
      end,
      {:desc, DateTime}
    )
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

  # Helper function to calculate donation amount for a single ticket
  defp get_donation_amount_for_single_ticket(ticket) do
    if ticket.ticket_order do
      # Reload the ticket order with all tickets to calculate donation amount
      ticket_order = Ysc.Tickets.get_ticket_order(ticket.ticket_order.id)

      if ticket_order && ticket_order.tickets do
        # Calculate non-donation ticket costs
        non_donation_total =
          ticket_order.tickets
          |> Enum.filter(fn t ->
            t.ticket_tier.type != "donation" && t.ticket_tier.type != :donation
          end)
          |> Enum.reduce(Money.new(0, :USD), fn t, acc ->
            case t.ticket_tier.price do
              nil ->
                acc

              price when is_struct(price, Money) ->
                case Money.add(acc, price) do
                  {:ok, new_total} -> new_total
                  _ -> acc
                end

              _ ->
                acc
            end
          end)

        # Calculate donation total
        donation_total =
          case Money.sub(ticket_order.total_amount, non_donation_total) do
            {:ok, amount} -> amount
            _ -> Money.new(0, :USD)
          end

        # Count donation tickets
        donation_tickets =
          ticket_order.tickets
          |> Enum.filter(fn t ->
            t.ticket_tier.type == "donation" || t.ticket_tier.type == :donation
          end)

        donation_count = length(donation_tickets)

        if donation_count > 0 && Money.positive?(donation_total) do
          # Calculate per-ticket donation amount
          per_ticket_amount =
            case Money.div(donation_total, donation_count) do
              {:ok, amount} -> amount
              _ -> Money.new(0, :USD)
            end

          # Format and display
          case Money.to_string(per_ticket_amount) do
            {:ok, amount} -> amount
            _ -> "Donation"
          end
        else
          "Donation"
        end
      else
        "Donation"
      end
    else
      "Donation"
    end
  end

  # Check if event is "selling fast" (based on recent ticket sales)
  # Uses the same logic as Events.event_selling_fast?/1:
  # An event is "selling fast" if it has sold 10 or more non-donation tickets in the last 3 days
  defp event_selling_fast?(event) do
    Events.event_selling_fast?(event.id)
  end

  # Calculate the percentage of tickets sold for an event
  defp get_event_sold_percentage(event) do
    if event.max_attendees != nil && event.max_attendees > 0 do
      case Ysc.Tickets.BookingLocker.check_availability_with_lock(event.id) do
        {:ok, availability} ->
          event_capacity = availability.event_capacity
          max_attendees = event_capacity.max_attendees

          if max_attendees != nil && max_attendees > 0 do
            current_attendees = event_capacity.current_attendees
            percentage = round(current_attendees / max_attendees * 100)
            min(percentage, 100)
          else
            nil
          end

        {:error, _} ->
          nil
      end
    else
      nil
    end
  end

  # Check if event is currently "live" (happening now in PST)
  defp event_live?(event) do
    if event.start_date != nil && event.start_time != nil &&
         event.end_time != nil do
      # Get current time in PST
      now_pst = DateTime.now!("America/Los_Angeles")
      now_time_pst = DateTime.to_time(now_pst)
      today_pst = DateTime.to_date(now_pst)

      # Get event date in PST
      event_date_pst =
        case event.start_date do
          %DateTime{} = dt ->
            dt_pst = DateTime.shift_zone!(dt, "America/Los_Angeles")
            DateTime.to_date(dt_pst)

          %Date{} = d ->
            d

          _ ->
            nil
        end

      # Check if event is happening today
      if event_date_pst == today_pst do
        # Get start and end times
        start_time = format_time(event.start_time)
        end_time = format_time(event.end_time)

        case {start_time, end_time} do
          {%Time{} = start, %Time{} = end_time_val} ->
            # Check if current time is between start and end times
            Time.compare(now_time_pst, start) != :lt &&
              Time.compare(now_time_pst, end_time_val) != :gt

          _ ->
            false
        end
      else
        false
      end
    else
      false
    end
  end

  # Check if an agenda item is currently happening (between start_time and end_time)
  # All comparisons are done in PST timezone since events are in PST
  defp agenda_item_current?(agenda_item, event) do
    # Only check if event is happening today and has start_date/start_time
    if event.start_date != nil && event.start_time != nil &&
         agenda_item.start_time != nil && agenda_item.end_time != nil do
      # Get current time in PST
      now_pst = DateTime.now!("America/Los_Angeles")
      now_time_pst = DateTime.to_time(now_pst)
      today_pst = DateTime.to_date(now_pst)

      # Get event date in PST (convert DateTime to PST first if needed, then get Date)
      event_date_pst =
        case event.start_date do
          %DateTime{} = dt ->
            # Convert UTC DateTime to PST, then get the date
            dt_pst = DateTime.shift_zone!(dt, "America/Los_Angeles")
            DateTime.to_date(dt_pst)

          %Date{} = d ->
            # Date structs don't have timezone, use as-is
            d

          _ ->
            nil
        end

      # Only show pulse if event is happening today (in PST)
      if event_date_pst == today_pst do
        # Check if current time (in PST) is between agenda item start and end times
        # Agenda item times are stored as Time structs and are in PST context
        Time.compare(now_time_pst, agenda_item.start_time) != :lt &&
          Time.compare(now_time_pst, agenda_item.end_time) != :gt
      else
        false
      end
    else
      false
    end
  end
end
