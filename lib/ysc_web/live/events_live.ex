defmodule YscWeb.EventsLive do
  use YscWeb, :live_view

  alias Ysc.Events
  alias Ysc.Media.Image
  alias Ysc.Tickets

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-6 md:py-12">
      <%!-- The "Masthead" Header --%>
      <div class="max-w-screen-xl mx-auto px-4 mb-16">
        <div class="text-center py-12 border-y border-zinc-200">
          <h1 class="text-6xl md:text-8xl font-black text-zinc-900 tracking-tighter">
            Events
          </h1>
        </div>
      </div>

      <%!-- Cinema Hero Layout - Next Event --%>
      <div :if={@hero_event != nil} class="max-w-screen-xl mx-auto px-4 mb-20">
        <div id="hero-event" class="group">
          <.link
            navigate={~p"/events/#{@hero_event.id}"}
            class="block hover:opacity-95 transition-opacity duration-300"
          >
            <div class="relative w-full aspect-[16/10] rounded-xl overflow-hidden shadow-2xl">
              <canvas
                id={"blur-hash-hero-#{@hero_event.id}"}
                src={get_blur_hash(@hero_event.image)}
                class="absolute inset-0 z-0 w-full h-full object-cover"
                phx-hook="BlurHashCanvas"
              >
              </canvas>
              <img
                src={event_image_url(@hero_event.image)}
                id={"image-hero-#{@hero_event.id}"}
                phx-hook="BlurHashImage"
                class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out object-cover w-full h-full group-hover:scale-105 transition-transform duration-700"
                loading="eager"
                alt={
                  if @hero_event.image,
                    do:
                      @hero_event.image.alt_text || @hero_event.image.title || @hero_event.title ||
                        "Event image",
                    else: "Event image"
                }
              />

              <%!-- Overlay gradient for text readability --%>
              <div class="absolute inset-0 z-[2] bg-gradient-to-t from-zinc-900/80 via-zinc-900/40 to-transparent">
              </div>

              <%!-- Content overlay --%>
              <div class="absolute inset-0 z-[3] flex flex-col justify-end p-8 md:p-12">
                <div class="max-w-3xl">
                  <div class="flex items-center gap-2 mb-4 flex-wrap">
                    <span class="px-3 py-1.5 bg-blue-500/90 backdrop-blur-md border border-blue-400 text-white text-xs font-black uppercase tracking-widest rounded-lg shadow-sm">
                      <.icon name="hero-calendar-solid" class="w-3.5 h-3.5 inline me-1" />Happening Soon
                    </span>
                    <%= for badge <- get_hero_event_badges(@hero_event) do %>
                      <span class={[
                        "px-3 py-1.5 backdrop-blur-md border rounded-lg text-xs font-black uppercase tracking-widest shadow-sm",
                        badge_class(badge)
                      ]}>
                        <.icon :if={badge.icon} name={badge.icon} class="w-3.5 h-3.5 inline me-1" />
                        <%= badge.text %>
                      </span>
                    <% end %>
                  </div>

                  <div class="flex items-center gap-3 mb-4 text-white/90">
                    <span class="text-sm md:text-base font-black text-white uppercase tracking-[0.2em]">
                      <%= format_event_date_time(@hero_event) %>
                    </span>
                    <span :if={@hero_event.location_name} class="h-4 w-px bg-white/40"></span>
                    <span
                      :if={@hero_event.location_name}
                      class="text-sm md:text-base font-bold text-white/80 uppercase tracking-widest"
                    >
                      <.icon name="hero-map-pin" class="w-4 h-4 inline me-1" />
                      <%= @hero_event.location_name %>
                    </span>
                  </div>

                  <h2 class="font-black text-zinc-50 text-4xl md:text-5xl lg:text-6xl leading-tight tracking-tighter mb-4 group-hover:text-white transition-colors">
                    <%= @hero_event.title %>
                  </h2>

                  <p
                    :if={@hero_event.description}
                    class="text-zinc-200 text-base md:text-lg leading-relaxed line-clamp-3 mb-6"
                  >
                    <%= @hero_event.description %>
                  </p>

                  <div class="flex items-center gap-3 pt-4 border-t border-white/20">
                    <span class="bg-white/90 backdrop-blur-md px-4 py-2 rounded-xl text-zinc-900 text-base font-black shadow-sm ring-1 ring-black/5">
                      <%= @hero_event.pricing_info.display_text %>
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </.link>
        </div>
      </div>

      <%!-- Main Content Grid with Sidebar --%>
      <div class="max-w-screen-xl mx-auto px-4 py-12">
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-12">
          <%!-- Events Grid --%>
          <div class="lg:col-span-9">
            <.live_component
              id="event_list"
              module={YscWeb.EventsListLive}
              exclude_event_id={if @hero_event, do: @hero_event.id, else: nil}
            />
          </div>

          <%!-- Sidebar --%>
          <aside class="lg:col-span-3">
            <div class="sticky top-24 space-y-8">
              <div class="p-8 bg-zinc-50 rounded-xl border border-zinc-100">
                <h4 class="text-[10px] font-black text-zinc-400 uppercase tracking-[0.2em] mb-6">
                  Upcoming Events
                </h4>
                <p class="text-sm text-zinc-600 leading-relaxed">
                  Explore our curated calendar of events. From social gatherings to cultural celebrations, there's always something happening at YSC.
                </p>
              </div>
            </div>
          </aside>
        </div>
      </div>

      <%!-- Memory Gallery - Past Events --%>
      <%= if @past_events_exist do %>
        <section class="mt-32 pt-16 border-t border-zinc-100">
          <div class="max-w-screen-xl mx-auto px-4">
            <h2 class="text-3xl font-black text-zinc-300 tracking-tighter italic mb-12">
              Past Events
            </h2>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div
                :for={{id, event} <- @streams.past_events}
                id={id}
                class="group relative aspect-video overflow-hidden rounded-2xl grayscale opacity-60 hover:opacity-100 hover:grayscale-0 transition-all duration-500 hover:scale-105 hover:rotate-1 ring-1 ring-zinc-200 shadow-sm hover:shadow-xl bg-white p-1"
              >
                <.link navigate={~p"/events/#{event.id}"} class="block w-full h-full">
                  <div class="w-full h-full overflow-hidden rounded-xl relative">
                    <canvas
                      id={"blur-hash-past-#{event.id}"}
                      src={get_blur_hash(event.image)}
                      class="absolute inset-0 z-0 w-full h-full object-cover"
                      phx-hook="BlurHashCanvas"
                    >
                    </canvas>
                    <img
                      src={event_image_url(event.image)}
                      id={"image-past-#{event.id}"}
                      phx-hook="BlurHashImage"
                      class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out object-cover w-full h-full group-hover:scale-110 transition-transform duration-700"
                      loading="lazy"
                      alt={
                        if event.image,
                          do:
                            event.image.alt_text || event.image.title || event.title || "Past event",
                          else: "Past event"
                      }
                    />
                    <%!-- Title overlay --%>
                    <div class="absolute inset-0 z-[2] bg-gradient-to-t from-zinc-900/80 via-zinc-900/40 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300">
                    </div>
                    <div class="absolute bottom-0 left-0 right-0 z-[3] p-3 opacity-0 group-hover:opacity-100 transition-opacity duration-300">
                      <h4 class="text-white text-sm font-black leading-tight line-clamp-2">
                        <%= event.title %>
                      </h4>
                      <p :if={event.start_date} class="text-white/80 text-xs font-medium mt-1">
                        <%= Timex.format!(event.start_date, "{Mshort} {D}, {YYYY}") %>
                      </p>
                    </div>
                  </div>
                </.link>
              </div>
            </div>

            <%= if @past_events_limit < 50 do %>
              <% has_more_events =
                Events.list_past_events(@past_events_limit + 1) |> length() > @past_events_limit %>
              <%= if has_more_events do %>
                <div class="text-center mt-12">
                  <.button phx-click="show_more_past_events" class="px-8 py-3">
                    Show More Past Events
                  </.button>
                </div>
              <% end %>
            <% end %>
          </div>
        </section>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Events.subscribe()
    end

    # Get the next upcoming event for hero
    upcoming_events = Events.list_upcoming_events(1)
    hero_event = List.first(upcoming_events)

    # Check if there are any past events
    past_events_limit = 10
    past_events_exist = Events.list_past_events(1) |> Enum.any?()
    past_events = if past_events_exist, do: Events.list_past_events(past_events_limit), else: []

    {:ok,
     socket
     |> assign(:page_title, "Events")
     |> assign(:hero_event, hero_event)
     |> assign(:past_events_exist, past_events_exist)
     |> assign(:past_events_limit, past_events_limit)
     |> stream(:past_events, past_events, reset: true)}
  end

  @impl true
  def handle_info({Ysc.Events, %_event{event: _} = base_event}, socket) do
    send_update(YscWeb.EventsListLive, id: "event_list", event: base_event)
    {:noreply, socket}
  end

  # Handle ticket tier events - refresh the associated event in the list
  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.TicketTierAdded{ticket_tier: ticket_tier}},
        socket
      ) do
    # Get the event and send an update to refresh it in the list
    case Events.get_event(ticket_tier.event_id) do
      nil ->
        {:noreply, socket}

      event ->
        event_updated = %Ysc.MessagePassingEvents.EventUpdated{event: event}
        send_update(YscWeb.EventsListLive, id: "event_list", event: event_updated)
        {:noreply, socket}
    end
  end

  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.TicketTierUpdated{ticket_tier: ticket_tier}},
        socket
      ) do
    # Get the event and send an update to refresh it in the list
    case Events.get_event(ticket_tier.event_id) do
      nil ->
        {:noreply, socket}

      event ->
        event_updated = %Ysc.MessagePassingEvents.EventUpdated{event: event}
        send_update(YscWeb.EventsListLive, id: "event_list", event: event_updated)
        {:noreply, socket}
    end
  end

  def handle_info(
        {Ysc.Events, %Ysc.MessagePassingEvents.TicketTierDeleted{ticket_tier: ticket_tier}},
        socket
      ) do
    # Get the event and send an update to refresh it in the list
    case Events.get_event(ticket_tier.event_id) do
      nil ->
        {:noreply, socket}

      event ->
        event_updated = %Ysc.MessagePassingEvents.EventUpdated{event: event}
        send_update(YscWeb.EventsListLive, id: "event_list", event: event_updated)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_more_past_events", _params, socket) do
    current_limit = socket.assigns.past_events_limit
    # Increase by 10, max 50
    new_limit = min(current_limit + 10, 50)
    past_events = Events.list_past_events(new_limit)

    {:noreply,
     socket
     |> assign(:past_events_limit, new_limit)
     |> stream(:past_events, past_events, reset: true)}
  end

  # Helper functions
  defp get_blur_hash(nil), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash

  defp event_image_url(nil), do: "/images/ysc_logo.png"
  defp event_image_url(%Image{optimized_image_path: nil} = image), do: image.raw_image_path
  defp event_image_url(%Image{optimized_image_path: optimized_path}), do: optimized_path

  defp format_event_date_time(event) do
    date_str = Timex.format!(event.start_date, "{Mshort} {D}")

    time_str =
      if event.start_time && event.start_time != "" do
        " • #{format_start_time(event.start_time)}"
      else
        ""
      end

    "#{date_str}#{time_str}"
  end

  defp format_start_time(time) when is_binary(time) do
    format_start_time(Timex.parse!(time, "{h12}:{m} {AM}"))
  end

  defp format_start_time(time) do
    Timex.format!(time, "{h12}:{m} {AM}")
  end

  defp get_hero_event_badges(event) do
    state = Map.get(event, :state) || Map.get(event, "state")
    sold_out = event_sold_out?(event)
    selling_fast = Map.get(event, :selling_fast, false)

    # If cancelled, only show "Cancelled" badge
    if state == :cancelled or state == "cancelled" do
      [%{text: "Cancelled", class: "bg-red-500/90 border-red-400 text-white", icon: nil}]
    else
      # If sold out (and not cancelled), only show "Sold Out" badge
      if sold_out do
        [%{text: "Sold Out", class: "bg-red-500/90 border-red-400 text-white", icon: nil}]
      else
        # Show active badges
        get_active_hero_badges(event, selling_fast)
      end
    end
  end

  defp get_active_hero_badges(event, selling_fast) do
    # Check if published_at exists (no badges for unpublished events)
    published_at = Map.get(event, :published_at) || Map.get(event, "published_at")

    if published_at != nil do
      badges = []

      # Add "Just Added" badge if applicable (within 48 hours of publishing)
      just_added_badge =
        if DateTime.diff(DateTime.utc_now(), published_at, :hour) <= 48 do
          [
            %{
              text: "Just Added",
              class: "bg-blue-500/90 border-blue-400 text-white",
              icon: nil
            }
          ]
        else
          []
        end

      badges = badges ++ just_added_badge

      # Add "Days Left" badge if applicable (1-3 days remaining)
      days_left = days_until_event_start(event)

      days_left_badge =
        if days_left != nil and days_left >= 1 and days_left <= 3 do
          text = "#{days_left} #{if days_left == 1, do: "day", else: "days"} left"
          [%{text: text, class: "bg-sky-500/90 border-sky-400 text-white", icon: nil}]
        else
          []
        end

      badges = badges ++ days_left_badge

      # Add "Selling Fast!" badge if applicable
      selling_fast_badge =
        if selling_fast do
          [
            %{
              text: "Selling Fast!",
              class: "bg-amber-500/90 border-amber-400 text-white",
              icon: "hero-bolt-solid"
            }
          ]
        else
          []
        end

      badges ++ selling_fast_badge
    else
      []
    end
  end

  defp badge_class(%{class: class}), do: class

  defp days_until_event_start(event) when is_map(event) do
    start_date = Map.get(event, :start_date)

    if start_date == nil do
      nil
    else
      now = DateTime.utc_now()

      # If event is in the past, return nil
      if DateTime.compare(now, start_date) == :gt do
        nil
      else
        # Calculate days difference using calendar days
        event_date_only = DateTime.to_date(start_date)
        now_date_only = DateTime.to_date(now)
        diff = Date.diff(event_date_only, now_date_only)
        max(0, diff)
      end
    end
  end

  defp event_sold_out?(event) do
    # Get event ID (handle both structs and maps)
    event_id = Map.get(event, :id) || Map.get(event, "id")

    # Use preloaded ticket_tiers if available (from batch loading), otherwise fetch
    ticket_tiers =
      case Map.get(event, :ticket_tiers) do
        nil -> Events.list_ticket_tiers_for_event(event_id)
        tiers -> tiers
      end

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
          # Include tiers that are on sale OR have ended their sale
          # Exclude tiers that haven't started their sale yet (pre-sale)
          tier_on_sale?(tier) || tier_sale_ended?(tier)
        end)

      # If there are no relevant tiers (all are pre-sale), event is not sold out
      if Enum.empty?(relevant_tiers) do
        false
      else
        # Check if all relevant non-donation tiers are sold out
        # A tier is sold out if available == 0 (unlimited tiers never count as sold out)
        all_tiers_sold_out =
          Enum.all?(relevant_tiers, fn tier ->
            available = get_available_quantity(tier)
            available == 0
          end)

        # Also check event capacity if max_attendees is set
        # (Note: This includes all tickets including donations, but if capacity is reached,
        #  all regular tickets are effectively sold out even if some tiers show availability)
        event_at_capacity =
          case Map.get(event, :max_attendees) || Map.get(event, "max_attendees") do
            nil ->
              false

            _ ->
              # Use preloaded ticket_count if available, otherwise query
              case Map.get(event, :ticket_count) do
                nil ->
                  Tickets.event_at_capacity?(event)

                ticket_count ->
                  max_attendees =
                    Map.get(event, :max_attendees) || Map.get(event, "max_attendees")

                  ticket_count >= max_attendees
              end
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
        nil -> true
        sd -> DateTime.compare(now, sd) != :lt
      end

    # Check if sale has ended
    sale_ended =
      case end_date do
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

  defp get_available_quantity(ticket_tier) do
    quantity = Map.get(ticket_tier, :quantity) || Map.get(ticket_tier, "quantity")

    sold_count =
      Map.get(ticket_tier, :sold_tickets_count) || Map.get(ticket_tier, "sold_tickets_count") || 0

    case quantity do
      # Unlimited
      nil ->
        :unlimited

      0 ->
        :unlimited

      qty ->
        available = qty - sold_count
        max(0, available)
    end
  end
end
