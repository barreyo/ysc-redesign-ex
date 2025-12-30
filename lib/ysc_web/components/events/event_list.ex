defmodule YscWeb.EventsListLive do
  use YscWeb, :live_component

  alias Ysc.Events
  alias Ysc.Tickets
  alias Ysc.Media.Image

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@event_count > 0} class="grid grid-cols-1 md:grid-cols-2 gap-8">
        <div
          :for={{id, event} <- @streams.events}
          class={[
            "group flex flex-col bg-white rounded-xl border border-zinc-100 shadow-sm hover:shadow-2xl hover:-translate-y-2 transition-all duration-500 overflow-hidden",
            event.state == :cancelled && "opacity-70"
          ]}
          id={id}
        >
          <.link navigate={~p"/events/#{event.id}"} class="block">
            <div class="relative aspect-video overflow-hidden">
              <canvas
                id={"blur-hash-card-#{event.id}"}
                src={get_blur_hash(event.image)}
                class="absolute inset-0 z-0 w-full h-full object-cover"
                phx-hook="BlurHashCanvas"
              >
              </canvas>
              <img
                src={event_image_url(event.image)}
                id={"image-card-#{event.id}"}
                phx-hook="BlurHashImage"
                class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out object-cover w-full h-full group-hover:scale-110 transition-transform duration-700"
                loading="lazy"
                alt={
                  if event.image,
                    do: event.image.alt_text || event.image.title || event.title || "Event image",
                    else: "Event image"
                }
              />
              <div class="absolute top-4 left-4 flex gap-2 z-[2] flex-wrap">
                <%= for badge <- get_event_badges_for_card(event) do %>
                  <span class={[
                    "px-3 py-1.5 rounded-lg text-xs font-black uppercase tracking-widest shadow-lg",
                    badge_class(badge)
                  ]}>
                    <.icon :if={badge.icon} name={badge.icon} class="w-3.5 h-3.5 inline me-0.5" />
                    <%= badge.text %>
                  </span>
                <% end %>
              </div>
              <div class="absolute bottom-4 right-4 z-[2]">
                <span class={[
                  "bg-white/90 backdrop-blur-md px-4 py-2 rounded-xl text-zinc-900 text-base font-black shadow-sm ring-1 ring-black/5",
                  event_sold_out?(event) && "line-through opacity-60"
                ]}>
                  <%= event.pricing_info.display_text %>
                </span>
              </div>
            </div>
          </.link>

          <div class="p-8 flex flex-col flex-1">
            <div class="flex items-center gap-2 mb-4">
              <span class="text-[10px] font-black text-blue-600 bg-blue-50 px-2 py-0.5 rounded uppercase tracking-[0.2em]">
                <%= format_event_date(event) %>
              </span>
              <span
                :if={event.start_time && event.start_time != ""}
                class="text-[10px] font-bold text-zinc-300 uppercase tracking-widest"
              >
                <%= format_start_time(event.start_time) %>
              </span>
            </div>
            <.link navigate={~p"/events/#{event.id}"} class="block">
              <h3 class="text-2xl font-black text-zinc-900 tracking-tighter leading-tight mb-4 group-hover:text-blue-600 transition-colors">
                <%= event.title %>
              </h3>
            </.link>
            <p
              :if={event.description}
              class="text-zinc-500 text-base leading-relaxed mb-6 line-clamp-2"
            >
              <%= event.description %>
            </p>

            <div class="mt-auto pt-6 border-t border-zinc-50 flex items-center justify-between">
              <span
                :if={event.location_name}
                class="text-sm font-bold text-zinc-400 flex items-center gap-1.5"
              >
                <.icon name="hero-map-pin" class="w-5 h-5" />
                <%= event.location_name %>
              </span>
              <span :if={!event.location_name}></span>
              <.icon
                name="hero-arrow-right"
                class="w-5 h-5 text-zinc-200 group-hover:text-blue-600 group-hover:translate-x-1 transition-all"
              />
            </div>
          </div>
        </div>
      </div>

      <div :if={@event_count == 0} class="flex flex-col items-center justify-center py-12">
        <div class="text-center justify-center items-center w-full">
          <img
            class="w-60 mx-auto rounded-full"
            src={~p"/images/vikings/viking_beer.png"}
            alt="No upcoming events at the moment"
          />
          <.header class="pt-8">
            No upcoming events at the moment
            <:subtitle>Check back soon again! We're always adding new events.</:subtitle>
          </.header>
        </div>
      </div>
    </div>
    """
  end

  def handle_info(
        %{event: %Ysc.MessagePassingEvents.EventAdded{event: event}},
        socket
      ) do
    {:noreply, socket |> stream_insert(:events, event)}
  end

  def handle_info(
        %{event: %Ysc.MessagePassingEvents.EventUpdated{event: event}},
        socket
      ) do
    {:noreply, socket |> stream_insert(:events, event)}
  end

  @impl true
  def update(assigns, socket) do
    upcoming = Map.get(assigns, :upcoming, true)
    limit = Map.get(assigns, :limit)
    exclude_event_id = Map.get(assigns, :exclude_event_id)

    events =
      if upcoming do
        all_events =
          if limit,
            do: Events.list_upcoming_events(limit + 1),
            else: Events.list_upcoming_events()

        # Filter out the hero event if specified
        filtered_events =
          if exclude_event_id do
            Enum.reject(all_events, fn event -> event.id == exclude_event_id end)
          else
            all_events
          end

        # Apply limit after filtering
        if limit, do: Enum.take(filtered_events, limit), else: filtered_events
      else
        if limit, do: Events.list_past_events(limit), else: Events.list_past_events()
      end

    {:ok,
     socket
     |> stream(:events, events, reset: true)
     |> assign(:event_count, length(events))
     |> assign(:upcoming, upcoming)
     |> assign(:limit, limit)
     |> assign(:exclude_event_id, exclude_event_id)}
  end

  defp format_start_time(time) when is_binary(time) do
    format_start_time(Timex.parse!(time, "{h12}:{m} {AM}"))
  end

  defp format_start_time(time) do
    Timex.format!(time, "{h12}:{m} {AM}")
  end

  defp format_event_date(event) do
    Timex.format!(event.start_date, "{Mshort} {D}")
  end

  defp get_blur_hash(nil), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash
  defp get_blur_hash(_), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"

  defp event_image_url(nil), do: "/images/ysc_logo.png"

  defp event_image_url(%Image{optimized_image_path: nil} = image),
    do: image.raw_image_path || "/images/ysc_logo.png"

  defp event_image_url(%Image{optimized_image_path: optimized_path}), do: optimized_path
  defp event_image_url(_), do: "/images/ysc_logo.png"

  defp get_event_badges_for_card(event) do
    state = Map.get(event, :state) || Map.get(event, "state")
    sold_out = event_sold_out?(event)
    selling_fast = Map.get(event, :selling_fast, false)

    # If cancelled, only show "Cancelled" badge
    if state == :cancelled or state == "cancelled" do
      [%{text: "Cancelled", class: "bg-red-500 text-white", icon: nil}]
    else
      # If sold out (and not cancelled), only show "Sold Out" badge
      if sold_out do
        [%{text: "Sold Out", class: "bg-red-500 text-white", icon: nil}]
      else
        # Show active badges
        get_active_badges_for_card(event, selling_fast)
      end
    end
  end

  defp get_active_badges_for_card(event, selling_fast) do
    # Check if published_at exists (no badges for unpublished events)
    published_at = Map.get(event, :published_at) || Map.get(event, "published_at")

    if published_at != nil do
      badges = []

      # Add "Just Added" badge if applicable (within 48 hours of publishing)
      just_added_badge =
        if DateTime.diff(DateTime.utc_now(), published_at, :hour) <= 48 do
          [%{text: "Just Added", class: "bg-blue-500 text-white", icon: nil}]
        else
          []
        end

      badges = badges ++ just_added_badge

      # Add "Days Left" badge if applicable (1-3 days remaining)
      days_left = days_until_event_start(event)

      days_left_badge =
        if days_left != nil and days_left >= 1 and days_left <= 3 do
          text = "#{days_left} #{if days_left == 1, do: "day", else: "days"} left"
          [%{text: text, class: "bg-sky-500 text-white", icon: nil}]
        else
          []
        end

      badges = badges ++ days_left_badge

      # Add "Selling Fast!" badge if applicable
      selling_fast_badge =
        if selling_fast do
          [%{text: "Selling Fast!", class: "bg-amber-500 text-white", icon: "hero-bolt-solid"}]
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
