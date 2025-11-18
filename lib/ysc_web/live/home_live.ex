defmodule YscWeb.HomeLive do
  use YscWeb, :live_view

  alias Ysc.{Accounts, Events, Subscriptions, Mailpoet}
  alias Ysc.Bookings.Booking
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      if user do
        # Load user with subscriptions and get membership info
        user_with_subs =
          Accounts.get_user!(user.id)
          |> Ysc.Repo.preload(subscriptions: :subscription_items)
          |> Accounts.User.populate_virtual_fields()

        current_membership = get_current_membership(user_with_subs)
        upcoming_tickets = get_upcoming_tickets(user.id)
        future_bookings = get_future_active_bookings(user.id)

        assign(socket,
          page_title: "Home",
          current_membership: current_membership,
          upcoming_tickets: upcoming_tickets,
          future_bookings: future_bookings,
          newsletter_email: "",
          newsletter_submitted: false,
          newsletter_error: nil
        )
      else
        assign(socket,
          page_title: "Home",
          newsletter_email: "",
          newsletter_submitted: false,
          newsletter_error: nil
        )
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-screen-lg mx-auto px-4 py-8 lg:py-10">
      <div class="max-w-xl mx-auto lg:mx-0 prose prose-zinc prose-base">
        <div :if={@current_user == nil} class="pb-10">
          <h1>Welcome to the Young Scandinavians Club!</h1>

          <p>
            The Young Scandinavians Club (YSC) is a vibrant community for Scandinavians and Scandinavian-Americans of all ages in the San Francisco Bay Area. We host a wide range of events across Northern California, offering members access to our scenic cabins in Clear Lake and Lake Tahoe. Year-round social and cultural gatherings bring our community together in and around San Francisco.
          </p>

          <div class="py-2">
            <.flag country="fi-dk" class="h-10 w-14 mr-2" />
            <.flag country="fi-fi" class="h-10 w-14 mr-2" />
            <.flag country="fi-is" class="h-10 w-14 mr-2" />
            <.flag country="fi-no" class="h-10 w-14 mr-2" />
            <.flag country="fi-se" class="h-10 w-14" />
          </div>

          <p>
            Those with <strong>Danish</strong>, <strong>Finnish</strong>, <strong>Icelandic</strong>, <strong>Norwegian</strong>, or
            <strong>Swedish</strong>
            heritage may qualify for membership, with rates starting at just
            <strong>
              <%= Ysc.MoneyHelper.format_money!(
                Money.new(:USD, Enum.at(Application.get_env(:ysc, :membership_plans), 0).amount)
              ) %>
            </strong>
            per year.
          </p>

          <div class="not-prose py-4">
            <.link
              navigate={~p"/users/register"}
              class="px-3 py-3 text-sm font-semibold leading-6 text-zinc-100 active:text-zinc-100/80 transition ease-in-out bg-blue-700 rounded duration-400 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300"
            >
              Apply for membership
            </.link>
          </div>

          <h2>Don't Let the Name Fool You –  The YSC is for Everyone!</h2>

          <p>
            We may be called the "Young" Scandinavians Club, but we're a community for all ages! Whether you're chasing toddlers around our Midsummer celebration or sharing stories by the fireplace at our Lake Tahoe cabin, you'll find your place at the YSC. With roughly 500 active members, we're a lively bunch who love to connect and have fun.
          </p>

          <p>
            Our events range from casual happy hours and hikes to formal dinners and holiday celebrations. We also host cultural events, such as lectures and film screenings, to help our members stay connected to their Scandinavian roots.
          </p>

          <p><strong>Your YSC membership unlocks:</strong></p>

          <ul>
            <li>
              <strong>Clear Lake Bliss:</strong>
              Imagine sunny days spent swimming, boating, and relaxing by the lake at our charming cabin.
            </li>
            <li>
              <strong>A Calendar Full of Fun:</strong>
              From festive Midsummer celebrations and cozy Christmas dinners to adventurous hikes and social happy hours, there's always something happening at the YSC.
            </li>
            <li>
              <strong>Tahoe Adventures:</strong>
              Picture yourself skiing down snowy slopes in the winter and hiking through breathtaking scenery in the summer – all from the comfort of our Lake Tahoe cabin.
            </li>
          </ul>

          <p><strong>We offer two membership options to fit your lifestyle:</strong></p>

          <ul>
            <li>
              <strong>
                Single Membership (<%= Ysc.MoneyHelper.format_money!(
                  Money.new(:USD, Enum.at(Application.get_env(:ysc, :membership_plans), 0).amount)
                ) %>/year):
              </strong>
              Enjoy all the benefits of the YSC for yourself.
            </li>
            <li>
              <strong>
                Family Membership (<%= Ysc.MoneyHelper.format_money!(
                  Money.new(:USD, Enum.at(Application.get_env(:ysc, :membership_plans), 1).amount)
                ) %>/year):
              </strong>
              Share the YSC experience with your loved ones! This affordable option covers you, your spouse, and your children under 18.
            </li>
          </ul>

          <div class="border-t border-1 border-zinc-100 mt-8">
            <h2>Newsletter</h2>
            <p>
              Sign up for our newsletter to receive updates about YSC and all the fun events we are arranging.
            </p>

            <form phx-submit="subscribe_newsletter" class="py-2">
              <label for="newsletter-email" class="sr-only">
                Email address
              </label>
              <input
                type="email"
                id="newsletter-email"
                name="email"
                value={@newsletter_email}
                class="px-3 py-2 block w-full border rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 border-zinc-300 focus:border-zinc-400 mb-4"
                placeholder="Email address"
                required
                disabled={@newsletter_submitted}
              />
              <p :if={@newsletter_error} class="text-sm text-red-600 mb-2">
                <%= @newsletter_error %>
              </p>
              <div :if={@newsletter_submitted} class="flex items-center mb-2">
                <.icon name="hero-check-circle" class="w-5 h-5 text-green-600 mr-2" />
                <p class="text-sm text-green-600">
                  Thank you for subscribing! Check your email to confirm.
                </p>
              </div>
              <.button :if={!@newsletter_submitted} type="submit">Let's keep in touch</.button>
              <p class="not-prose text-sm italic text-zinc-500 mt-2">
                We don't spam! Read our
                <.link navigate={~p"/privacy-policy"} class="text-blue-600 hover:underline">
                  privacy policy
                </.link>
                for more info.
              </p>
            </form>
          </div>
        </div>

        <div :if={@current_user != nil}>
          <div class="space-y-10 md:space-y-16">
            <!-- Welcome Section -->
            <div>
              <h1>
                Welcome back, <%= String.capitalize(@current_user.first_name) %>!
              </h1>
            </div>

            <div class="space-y-10 md:space-y-16 not-prose">
              <!-- Membership Status Section -->
              <div class="flex flex-col space-y-4">
                <div class="flex flex-row justify-between space-x-4">
                  <div class="flex-shrink-0">
                    <h2 class="text-xl md:text-2xl font-semibold text-zinc-900">Membership Status</h2>
                  </div>
                  <div class="flex-shrink-0">
                    <.button phx-click={JS.navigate(~p"/users/membership")}>
                      Manage membership
                    </.button>
                  </div>
                </div>

                <div class="w-full">
                  <.membership_status current_membership={@current_membership} />
                </div>
              </div>
              <!-- Upcoming Bookings Section -->
              <div class="space-y-4 flex flex-col">
                <div class="flex flex-row justify-between items-center space-x-4">
                  <div class="flex-shrink-0">
                    <h2 class="text-xl md:text-2xl font-semibold text-zinc-900">
                      Your Upcoming Bookings
                    </h2>
                  </div>
                  <div class="flex-shrink-0 flex gap-2">
                    <.button phx-click={JS.navigate(~p"/bookings/tahoe")}>
                      Book Tahoe
                    </.button>
                    <.button phx-click={JS.navigate(~p"/bookings/clear-lake")}>
                      Book Clear Lake
                    </.button>
                  </div>
                </div>

                <div :if={Enum.empty?(@future_bookings)} class="text-center py-4">
                  <div class="flex justify-center mb-4">
                    <.icon name="hero-home" class="w-12 h-12 text-zinc-400" />
                  </div>
                  <h3 class="text-lg font-medium text-zinc-900 mb-2">No upcoming bookings</h3>
                  <p class="text-zinc-600 mb-4">
                    You don't have any cabin bookings scheduled yet.
                  </p>
                </div>

                <div :if={!Enum.empty?(@future_bookings)} class="space-y-4">
                  <%= for booking <- @future_bookings do %>
                    <div class="border border-zinc-200 rounded-lg p-4 hover:bg-zinc-50 transition-colors">
                      <div class="flex items-start justify-between">
                        <div class="flex-1">
                          <div class="flex items-center gap-2 mb-2">
                            <.link
                              navigate={~p"/bookings/#{booking.id}"}
                              class="hover:text-blue-600 transition-colors"
                            >
                              <.badge>
                                <%= booking.reference_id %>
                              </.badge>
                            </.link>
                            <span class="text-sm font-medium text-zinc-900">
                              <%= format_property_name(booking.property) %>
                            </span>
                            <%= if Ecto.assoc_loaded?(booking.rooms) && length(booking.rooms) > 0 do %>
                              <span class="text-sm text-zinc-600">
                                · <%= Enum.map_join(booking.rooms, ", ", fn room -> room.name end) %>
                              </span>
                            <% else %>
                              <span class="text-sm text-zinc-600">· Full Buyout</span>
                            <% end %>
                          </div>
                          <div class="flex items-center text-sm text-zinc-600 mb-1">
                            <.icon name="hero-calendar-days" class="w-4 h-4 mr-1" />
                            <span class="font-semibold">Check-in:</span>
                            <span class="ml-1">
                              <%= Calendar.strftime(booking.checkin_date, "%B %d, %Y") %>
                            </span>
                            <span class="ml-2 text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded inline-block">
                              <%= case days_until_booking(booking) do
                                :started -> "In progress"
                                0 -> "Today"
                                1 -> "1 day left"
                                days -> "#{days} days left"
                              end %>
                            </span>
                          </div>
                          <div class="flex items-center text-sm text-zinc-600 mb-1">
                            <.icon name="hero-calendar-days" class="w-4 h-4 mr-1" />
                            <span class="font-semibold">Check-out:</span>
                            <span class="ml-1">
                              <%= Calendar.strftime(booking.checkout_date, "%B %d, %Y") %>
                            </span>
                          </div>
                          <div class="flex items-center text-sm text-zinc-600">
                            <.icon name="hero-users" class="w-4 h-4 mr-1" />
                            <%= booking.guests_count %> <%= if booking.guests_count == 1,
                              do: "guest",
                              else: "guests" %>
                            <%= if booking.children_count > 0 do %>
                              , <%= booking.children_count %> <%= if booking.children_count == 1,
                                do: "child",
                                else: "children" %>
                            <% end %>
                          </div>
                        </div>
                        <div class="ml-4 flex-shrink-0">
                          <.link
                            navigate={~p"/bookings/#{booking.id}"}
                            class="text-blue-600 hover:text-blue-800 text-sm font-medium"
                          >
                            View Details →
                          </.link>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
              <!-- Upcoming Tickets Section -->
              <div class="space-y-4 flex flex-col">
                <div class="flex flex-row justify-between items-center space-x-4">
                  <div class="flex-shrink-0">
                    <h2 class="text-xl md:text-2xl font-semibold text-zinc-900">
                      Your Upcoming Events
                    </h2>
                  </div>
                  <div class="flex-shrink-0">
                    <.button phx-click={JS.navigate(~p"/events")}>
                      Browse all events
                    </.button>
                  </div>
                </div>

                <div :if={Enum.empty?(@upcoming_tickets)} class="text-center py-4">
                  <div class="flex justify-center mb-4">
                    <.icon name="hero-calendar-days" class="w-12 h-12 text-zinc-400" />
                  </div>
                  <h3 class="text-lg font-medium text-zinc-900 mb-2">No upcoming events</h3>
                  <p class="text-zinc-600 mb-4">
                    You don't have any tickets for upcoming events yet.
                  </p>
                </div>

                <div :if={!Enum.empty?(@upcoming_tickets)} class="space-y-4">
                  <%= for {event, grouped_tiers} <- group_tickets_by_event_and_tier(@upcoming_tickets) do %>
                    <div class="border border-zinc-200 rounded-lg p-4">
                      <div class="flex items-start justify-between mb-4">
                        <div class="flex-1">
                          <div class="flex items-center w-full justify-between">
                            <h3 class="text-lg font-medium text-zinc-900 mb-1 flex-shrink-0">
                              <%= event.title %>
                            </h3>

                            <div class="ml-4 flex-shrink-0">
                              <.link
                                navigate={~p"/events/#{event.id}"}
                                class="text-blue-600 hover:text-blue-800 text-sm font-medium"
                              >
                                View Event →
                              </.link>
                            </div>
                          </div>

                          <div class="flex items-center text-sm text-zinc-600 mb-2">
                            <.icon name="hero-calendar-days" class="w-4 h-4 mr-1" />
                            <%= Calendar.strftime(event.start_date, "%B %d, %Y at %I:%M %p") %>
                            <span class="ml-2 text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded inline-block">
                              <%= case days_until_event(event) do
                                0 -> "Today"
                                1 -> "1 day left"
                                days -> "#{days} days left"
                              end %>
                            </span>
                          </div>
                          <div
                            :if={event.location_name}
                            class="flex items-center text-sm text-zinc-600 mb-2"
                          >
                            <.icon name="hero-map-pin" class="w-4 h-4 mr-1" />
                            <%= event.location_name %>
                          </div>
                        </div>
                      </div>
                      <!-- Grouped Tickets by Tier -->
                      <div class="space-y-2">
                        <%= for {tier_name, tickets} <- grouped_tiers do %>
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
                                    <%= get_donation_amount_display(tickets) %>
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
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp get_current_membership(user) do
    # Check for lifetime membership first
    if Accounts.has_lifetime_membership?(user) do
      lifetime_plan =
        Application.get_env(:ysc, :membership_plans)
        |> Enum.find(&(&1.id == :lifetime))

      %{
        plan: lifetime_plan,
        type: :lifetime,
        awarded_at: user.lifetime_membership_awarded_at,
        renewal_date: nil
      }
    else
      # Get active subscriptions
      active_subscriptions =
        user.subscriptions
        |> Enum.filter(fn sub -> Subscriptions.valid?(sub) and sub.stripe_status == "active" end)

      case active_subscriptions do
        [] ->
          nil

        [subscription | _] ->
          # Get the first subscription item to determine membership type
          case subscription.subscription_items do
            [item | _] ->
              membership_plans = Application.get_env(:ysc, :membership_plans)
              plan = Enum.find(membership_plans, &(&1.stripe_price_id == item.stripe_price_id))

              if plan do
                %{
                  plan: plan,
                  subscription: subscription,
                  renewal_date: subscription.current_period_end
                }
              else
                nil
              end

            [] ->
              nil
          end
      end
    end
  end

  defp get_upcoming_tickets(user_id, limit \\ 10) do
    # Get all confirmed tickets for the user
    tickets = Events.list_tickets_for_user(user_id)

    # Filter for upcoming events only and confirmed tickets
    now = DateTime.utc_now()

    tickets
    |> Enum.filter(fn ticket ->
      ticket.status == :confirmed and
        case ticket.event do
          %{start_date: start_date} when not is_nil(start_date) ->
            DateTime.compare(start_date, now) == :gt

          _ ->
            false
        end
    end)
    |> Enum.sort_by(fn ticket -> ticket.event.start_date end, :asc)
    |> Enum.take(limit)
  end

  defp group_tickets_by_tier(tickets) do
    tickets
    |> Enum.group_by(& &1.ticket_tier.name)
    |> Enum.sort_by(fn {_tier_name, tickets} -> length(tickets) end, :desc)
  end

  defp group_tickets_by_event_and_tier(tickets) do
    tickets
    |> Enum.group_by(& &1.event.id)
    |> Enum.map(fn {_event_id, event_tickets} ->
      event = List.first(event_tickets).event
      grouped_tiers = group_tickets_by_tier(event_tickets)
      {event, grouped_tiers}
    end)
    |> Enum.sort_by(fn {event, _tiers} -> event.start_date end, :asc)
  end

  defp get_future_active_bookings(user_id, limit \\ 10) do
    today = Date.utc_today()
    checkout_time = ~T[11:00:00]

    query =
      from b in Booking,
        where: b.user_id == ^user_id,
        where: b.status == :complete,
        where: b.checkout_date >= ^today,
        order_by: [asc: b.checkin_date],
        limit: ^limit,
        preload: [:rooms]

    bookings = Ysc.Repo.all(query)

    # Filter out bookings that are past checkout time today
    bookings
    |> Enum.filter(fn booking ->
      if Date.compare(booking.checkout_date, today) == :eq do
        now = DateTime.utc_now()
        checkout_datetime = DateTime.new!(today, checkout_time, "Etc/UTC")
        DateTime.compare(now, checkout_datetime) == :lt
      else
        true
      end
    end)
    |> Enum.take(limit)
  end

  defp get_donation_amount_display(tickets) do
    # Get the ticket_order from the first ticket
    ticket_order = List.first(tickets).ticket_order

    if ticket_order do
      # Get all tickets in the order (we need to reload with all tickets)
      order_with_tickets = Ysc.Tickets.get_ticket_order(ticket_order.id)

      if order_with_tickets && order_with_tickets.tickets do
        # Calculate non-donation ticket costs
        non_donation_total =
          order_with_tickets.tickets
          |> Enum.filter(fn t ->
            t.ticket_tier.type != "donation" && t.ticket_tier.type != :donation
          end)
          |> Enum.reduce(Money.new(0, :USD), fn ticket, acc ->
            case ticket.ticket_tier.price do
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
          case Money.sub(order_with_tickets.total_amount, non_donation_total) do
            {:ok, amount} -> amount
            _ -> Money.new(0, :USD)
          end

        # Count donation tickets
        donation_tickets =
          order_with_tickets.tickets
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

  defp format_property_name(:tahoe), do: "Lake Tahoe"
  defp format_property_name(:clear_lake), do: "Clear Lake"
  defp format_property_name(_), do: "Unknown"

  defp days_until_booking(booking) do
    today = Date.utc_today()
    checkin_date = booking.checkin_date

    case Date.compare(today, checkin_date) do
      # Check-in is in the past - booking has started
      :gt ->
        :started

      # Check-in is today
      :eq ->
        0

      # Check-in is in the future
      :lt ->
        # Calculate days difference using calendar days
        diff = Date.diff(checkin_date, today)
        diff
    end
  end

  defp days_until_event(event) do
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

    case DateTime.compare(now, event_datetime) do
      # Event is in the past
      :gt ->
        0

      _ ->
        # Calculate days difference using calendar days, not 24-hour periods
        # This ensures that an event tomorrow shows as "1 day left" even if it's less than 24 hours away
        event_date_only = DateTime.to_date(event_datetime)
        now_date_only = DateTime.to_date(now)
        diff = Date.diff(event_date_only, now_date_only)
        max(0, diff)
    end
  end

  @impl true
  def handle_event("subscribe_newsletter", %{"email" => email}, socket) do
    case Mailpoet.subscribe_email(email) do
      {:ok, _response} ->
        {:noreply,
         socket
         |> assign(
           newsletter_email: email,
           newsletter_submitted: true,
           newsletter_error: nil
         )
         |> put_flash(:info, "Thank you for subscribing to our newsletter!")}

      {:error, :invalid_email} ->
        {:noreply,
         socket
         |> assign(
           newsletter_email: email,
           newsletter_error: "Please enter a valid email address."
         )}

      {:error, :mailpoet_api_url_not_configured} ->
        {:noreply,
         socket
         |> assign(
           newsletter_email: email,
           newsletter_error: "Newsletter service is not configured. Please contact support."
         )}

      {:error, :mailpoet_api_key_not_configured} ->
        {:noreply,
         socket
         |> assign(
           newsletter_email: email,
           newsletter_error: "Newsletter service is not configured. Please contact support."
         )}

      {:error, error_message} when is_binary(error_message) ->
        {:noreply,
         socket
         |> assign(
           newsletter_email: email,
           newsletter_error: "Unable to subscribe at this time. Please try again later."
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(
           newsletter_email: email,
           newsletter_error: "Unable to subscribe at this time. Please try again later."
         )}
    end
  end
end
