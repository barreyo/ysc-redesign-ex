defmodule YscWeb.HomeLive do
  use YscWeb, :live_view

  alias Ysc.{Accounts, Events, Posts, Subscriptions, Mailpoet, Tickets}
  alias Ysc.Bookings.{Booking, Season}
  alias Ysc.Posts.Post
  alias Ysc.Media.Image
  alias HtmlSanitizeEx.Scrubber
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

        # Use current_membership from socket assigns (set by on_mount hook)
        # which already handles sub-accounts correctly
        current_membership =
          socket.assigns.current_membership || get_current_membership(user_with_subs)

        # Check if user is a sub-account and get primary user
        is_sub_account = Accounts.is_sub_account?(user_with_subs)
        primary_user = if is_sub_account, do: Accounts.get_primary_user(user_with_subs), else: nil

        upcoming_tickets = get_upcoming_tickets(user.id)
        future_bookings = get_future_active_bookings(user.id)
        upcoming_events = Events.list_upcoming_events(3)
        latest_news = Posts.list_posts(3)

        assign(socket,
          page_title: "Home",
          current_membership: current_membership,
          is_sub_account: is_sub_account,
          primary_user: primary_user,
          upcoming_tickets: upcoming_tickets,
          future_bookings: future_bookings,
          upcoming_events: upcoming_events,
          latest_news: latest_news,
          newsletter_email: "",
          newsletter_submitted: false,
          newsletter_error: nil
        )
      else
        upcoming_events = Events.list_upcoming_events(3)
        latest_news = Posts.list_posts(3)

        # Determine hero video based on current Tahoe season
        # Use Clear Lake video during summer, Tahoe video otherwise
        hero_video =
          case Season.for_date(:tahoe, Date.utc_today()) do
            %{name: "Summer"} -> ~p"/video/clear_lake_hero.mp4"
            _ -> ~p"/video/tahoe_hero.mp4"
          end

        assign(socket,
          page_title: "Home",
          upcoming_events: upcoming_events,
          latest_news: latest_news,
          hero_video: hero_video,
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
    <div :if={@current_user == nil}>
      <.hero video={@hero_video} height="90vh" overlay_opacity="bg-black/40">
        <div class="mb-6 pt-6">
          <span class="inline-block px-4 py-1.5 text-sm font-semibold tracking-widest uppercase bg-white/10 backdrop-blur-sm rounded-full border border-white/20 text-white/90">
            Est. 1950 · San Francisco
          </span>
        </div>

        <h1 class="text-5xl md:text-6xl lg:text-7xl font-black tracking-tight text-white drop-shadow-2xl pb-2">
          <span class="block font-light text-3xl md:text-4xl lg:text-5xl mb-2 text-white/90">
            Welcome to the
          </span>
          <span class="block">Young Scandinavians</span>
          <span class="block mt-1">Club</span>
        </h1>

        <p class="mt-8 text-lg md:text-xl lg:text-2xl max-w-2xl mx-auto text-white/85 font-light leading-relaxed drop-shadow-md">
          A vibrant community for Scandinavians and Scandinavian-Americans in and around the San Francisco Bay Area
        </p>

        <div class="mt-10 flex flex-wrap gap-4 justify-center">
          <.link
            navigate={~p"/users/register"}
            class="group px-8 py-4 text-base font-bold text-zinc-900 bg-white rounded-lg hover:bg-blue-50 transition-all duration-300 shadow-lg hover:shadow-xl hover:scale-105"
          >
            Apply for Membership
            <.icon
              name="hero-arrow-right"
              class="me-2 w-5 h-5 group-hover:translate-x-1 transition-transform duration-300"
            />
          </.link>
          <.link
            navigate={~p"/events"}
            class="px-8 py-4 text-base font-bold text-white border-2 border-white/80 rounded-lg hover:bg-white hover:text-zinc-900 transition-all duration-300 backdrop-blur-sm"
          >
            View Events
          </.link>
        </div>

        <div class="mt-16 flex items-center justify-center gap-8 text-white/70">
          <div class="text-center">
            <div class="text-3xl font-bold text-white">500+</div>
            <div class="text-sm uppercase tracking-wide">Members</div>
          </div>
          <div class="w-px h-12 bg-white/30"></div>
          <div class="text-center">
            <div class="text-3xl font-bold text-white">2</div>
            <div class="text-sm uppercase tracking-wide">Cabins</div>
          </div>
          <div class="w-px h-12 bg-white/30"></div>
          <div class="text-center">
            <div class="text-3xl font-bold text-white"><%= Date.utc_today().year - 1950 %>+</div>
            <div class="text-sm uppercase tracking-wide">Years</div>
          </div>
        </div>
      </.hero>
    </div>

    <%!-- About Section --%>
    <section :if={@current_user == nil} class="py-16 lg:py-24 bg-white">
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="grid lg:grid-cols-2 gap-12 lg:gap-16 items-center">
          <div>
            <span class="text-blue-600 font-semibold text-sm uppercase tracking-wider">About Us</span>
            <h2 class="mt-3 text-3xl lg:text-4xl font-bold text-zinc-900 leading-tight">
              A Community Rooted in Scandinavian Heritage
            </h2>
            <p class="mt-6 text-lg text-zinc-600 leading-relaxed">
              The Young Scandinavians Club (YSC) is a vibrant community for Scandinavians and Scandinavian-Americans of all ages in the San Francisco Bay Area. We host a wide range of events across Northern California, offering members access to our scenic cabins in Clear Lake and Lake Tahoe.
            </p>
            <div class="mt-6 flex items-center gap-3">
              <.flag country="fi-dk" class="h-8 w-12 rounded shadow-sm" />
              <.flag country="fi-fi" class="h-8 w-12 rounded shadow-sm" />
              <.flag country="fi-is" class="h-8 w-12 rounded shadow-sm" />
              <.flag country="fi-no" class="h-8 w-12 rounded shadow-sm" />
              <.flag country="fi-se" class="h-8 w-12 rounded shadow-sm" />
            </div>
            <p class="mt-6 text-zinc-600">
              Those with <strong class="text-zinc-900">Danish</strong>, <strong class="text-zinc-900">Finnish</strong>, <strong class="text-zinc-900">Icelandic</strong>, <strong class="text-zinc-900">Norwegian</strong>, or
              <strong class="text-zinc-900">Swedish</strong>
              heritage may qualify for membership, with rates starting at just
              <strong class="text-blue-600">
                <%= Ysc.MoneyHelper.format_money!(
                  Money.new(:USD, Enum.at(Application.get_env(:ysc, :membership_plans), 0).amount)
                ) %>
              </strong>
              per year.
            </p>
            <div class="mt-8">
              <.link
                navigate={~p"/users/register"}
                class="inline-flex items-center px-6 py-3 text-base font-bold text-white bg-blue-600 rounded-lg hover:bg-blue-700 transition duration-300 shadow-lg hover:shadow-xl"
              >
                Apply for Membership <.icon name="hero-arrow-right" class="ml-2 w-5 h-5" />
              </.link>
            </div>
          </div>
          <div class="relative">
            <img
              src={~p"/images/ysc_75th.jpg"}
              alt="YSC 75th Anniversary"
              class="w-full rounded-2xl shadow-2xl"
            />
          </div>
        </div>
      </div>
    </section>

    <%!-- Community Highlight Section --%>
    <section :if={@current_user == nil} class="py-16 lg:py-24 bg-zinc-50">
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="text-center max-w-3xl mx-auto mb-12">
          <span class="text-blue-600 font-semibold text-sm uppercase tracking-wider">
            Our Community
          </span>
          <h2 class="mt-3 text-3xl lg:text-4xl font-bold text-zinc-900">
            Don't Let the Name Fool You – YSC is for Everyone!
          </h2>
          <p class="mt-4 text-lg text-zinc-600">
            We may be called the "Young" Scandinavians Club, but we're a community for all ages! With roughly 500 active members, we're a lively bunch who love to connect and have fun.
          </p>
        </div>

        <div class="grid md:grid-cols-3 gap-6">
          <div class="bg-white rounded-2xl overflow-hidden shadow-lg hover:shadow-xl transition-shadow">
            <img
              src={~p"/images/ysc_bonfire_2024.jpg"}
              alt="YSC Bonfire 2024"
              class="w-full aspect-[4/3] object-cover"
            />
            <div class="p-6">
              <h3 class="text-xl font-bold text-zinc-900">Events Year-Round</h3>
              <p class="mt-2 text-zinc-600">
                From casual happy hours to formal dinners and holiday celebrations.
              </p>
            </div>
          </div>
          <div class="bg-white rounded-2xl overflow-hidden shadow-lg hover:shadow-xl transition-shadow">
            <img
              src={~p"/images/clear_lake_midsummer.jpg"}
              alt="Midsummer at Clear Lake"
              class="w-full aspect-[4/3] object-cover"
            />
            <div class="p-6">
              <h3 class="text-xl font-bold text-zinc-900">All Ages Welcome</h3>
              <p class="mt-2 text-zinc-600">
                Whether chasing toddlers at Midsummer or sharing stories by the fireplace everyone is welcome.
              </p>
            </div>
          </div>
          <div class="bg-white rounded-2xl overflow-hidden shadow-lg hover:shadow-xl transition-shadow">
            <img
              src={~p"/images/flags.jpg"}
              alt="Nordic country flags"
              class="w-full aspect-[4/3] object-cover"
            />
            <div class="p-6">
              <h3 class="text-xl font-bold text-zinc-900">Cultural Connection</h3>
              <p class="mt-2 text-zinc-600">
                Lectures, film screenings, and traditions to stay connected to your roots.
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>

    <%!-- Cabins Section --%>
    <section :if={@current_user == nil} class="py-16 lg:py-24 bg-white">
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="text-center max-w-3xl mx-auto mb-16">
          <span class="text-blue-600 font-semibold text-sm uppercase tracking-wider">
            Our Properties
          </span>
          <h2 class="mt-3 text-3xl lg:text-4xl font-bold text-zinc-900">
            Two Beautiful Cabin Retreats
          </h2>
          <p class="mt-4 text-lg text-zinc-600">
            Your YSC membership unlocks access to our scenic cabins for unforgettable getaways.
          </p>
        </div>

        <%!-- Lake Tahoe --%>
        <div class="grid lg:grid-cols-2 gap-8 lg:gap-12 items-center mb-20">
          <div class="order-2 lg:order-1">
            <div class="inline-flex items-center px-3 py-1 bg-blue-100 text-blue-700 rounded-full text-sm font-medium mb-4">
              <.icon name="hero-map-pin" class="w-4 h-4 mr-1" /> Lake Tahoe, CA
            </div>
            <h3 class="text-2xl lg:text-3xl font-bold text-zinc-900">Tahoe Cabin</h3>
            <p class="mt-4 text-lg text-zinc-600 leading-relaxed">
              Ski in winter, hike in summer, and relax year-round at our beautiful Lake Tahoe retreat. The cabin offers stunning mountain views and is perfectly positioned for all your alpine adventures. Adult rates only <strong>$45.00 / night per person</strong>.
            </p>
            <ul class="mt-6 space-y-3">
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check-circle" class="w-5 h-5 text-emerald-500 mr-3" />
                Year-round access for members
              </li>
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check-circle" class="w-5 h-5 text-emerald-500 mr-3" />
                Minutes from world-class ski resorts
              </li>
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check-circle" class="w-5 h-5 text-emerald-500 mr-3" />
                Hiking trails at your doorstep
              </li>
            </ul>
            <.link
              navigate={~p"/bookings/tahoe"}
              class="mt-8 inline-flex items-center text-blue-600 font-semibold hover:text-blue-700 transition"
            >
              Learn more about Tahoe Cabin <.icon name="hero-arrow-right" class="ml-2 w-5 h-5" />
            </.link>
          </div>
          <div class="order-1 lg:order-2">
            <img
              src={~p"/images/tahoe/tahoe_cabin_main.webp"}
              alt="Lake Tahoe Cabin"
              class="rounded-2xl shadow-2xl w-full aspect-[4/3] object-cover"
            />
          </div>
        </div>

        <%!-- Clear Lake --%>
        <div class="grid lg:grid-cols-2 gap-8 lg:gap-12 items-center">
          <div>
            <img
              src={~p"/images/clear_lake/clear_lake_dock.webp"}
              alt="Clear Lake Cabin"
              class="rounded-2xl shadow-2xl w-full aspect-[4/3] object-cover"
            />
          </div>
          <div>
            <div class="inline-flex items-center px-3 py-1 bg-emerald-100 text-emerald-700 rounded-full text-sm font-medium mb-4">
              <.icon name="hero-map-pin" class="w-4 h-4 mr-1" /> Clear Lake, CA
            </div>
            <h3 class="text-2xl lg:text-3xl font-bold text-zinc-900">Clear Lake Cabin</h3>
            <p class="mt-4 text-lg text-zinc-600 leading-relaxed">
              Swim, boat, and unwind at our peaceful lakeside cabin. Clear Lake offers the perfect escape for water lovers and those seeking tranquility away from the city. Rates start at <strong>$50.00 / night</strong>.
            </p>
            <ul class="mt-6 space-y-3">
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check-circle" class="w-5 h-5 text-emerald-500 mr-3" />
                Direct lake access with private dock
              </li>
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check-circle" class="w-5 h-5 text-emerald-500 mr-3" />
                Perfect for swimming and boating
              </li>
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check-circle" class="w-5 h-5 text-emerald-500 mr-3" />
                Peaceful lakeside relaxation
              </li>
            </ul>
            <.link
              navigate={~p"/bookings/clear-lake"}
              class="mt-8 inline-flex items-center text-blue-600 font-semibold hover:text-blue-700 transition"
            >
              Learn more about Clear Lake Cabin <.icon name="hero-arrow-right" class="ml-2 w-5 h-5" />
            </.link>
          </div>
        </div>
      </div>
    </section>

    <%!-- Upcoming Events Section --%>
    <section
      :if={@current_user == nil && length(@upcoming_events) > 0}
      class="py-16 lg:py-24 bg-zinc-900"
    >
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between mb-12">
          <div>
            <span class="text-blue-400 font-semibold text-sm uppercase tracking-wider">
              What's Happening
            </span>
            <h2 class="mt-3 text-3xl lg:text-4xl font-bold text-white">
              Upcoming Events
            </h2>
          </div>
          <.link
            navigate={~p"/events"}
            class="mt-4 sm:mt-0 inline-flex items-center text-blue-400 font-semibold hover:text-blue-300 transition"
          >
            View all events <.icon name="hero-arrow-right" class="ml-2 w-5 h-5" />
          </.link>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <%= for event <- @upcoming_events do %>
            <div class={[
              "flex flex-col rounded",
              event.state == :cancelled && "opacity-70"
            ]}>
              <.link
                navigate={~p"/events/#{event.id}"}
                class="w-full hover:opacity-80 transition duration-200 transition-opacity ease-in-out"
              >
                <.live_component
                  id={"home-event-cover-#{event.id}"}
                  module={YscWeb.Components.Image}
                  image_id={event.image_id}
                  image={Map.get(event, :image)}
                />
              </.link>

              <div class="flex flex-col py-3 px-2 space-y-2">
                <div>
                  <.event_badge
                    event={event}
                    sold_out={event_sold_out?(event)}
                    selling_fast={Map.get(event, :selling_fast, false)}
                  />
                </div>

                <.link
                  navigate={~p"/events/#{event.id}"}
                  class="text-2xl md:text-xl leading-6 font-semibold text-white text-pretty"
                >
                  <%= event.title %>
                </.link>

                <div class="space-y-0.5">
                  <p class="font-semibold text-sm text-zinc-200">
                    <%= Timex.format!(event.start_date, "{WDshort}, {Mshort} {D}") %><span :if={
                      event.start_time != nil && event.start_time != ""
                    }>
                    • <%= format_start_time(event.start_time) %>
                  </span>
                  </p>

                  <p
                    :if={event.location_name != nil && event.location_name != ""}
                    class="text-zinc-300 text-sm"
                  >
                    <%= event.location_name %>
                  </p>
                </div>

                <p class="text-sm text-pretty text-zinc-400 py-1"><%= event.description %></p>

                <div :if={event.state != :cancelled} class="flex flex-row space-x-2 pt-2 items-center">
                  <p class={[
                    "text-sm font-semibold",
                    if event_sold_out?(event) do
                      "text-zinc-300 line-through"
                    else
                      "text-zinc-200"
                    end
                  ]}>
                    <%= event.pricing_info.display_text %>
                  </p>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </section>

    <%!-- Latest News Section --%>
    <section :if={@current_user == nil && length(@latest_news) > 0} class="py-16 lg:py-24 bg-zinc-50">
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between mb-12">
          <div>
            <span class="text-blue-600 font-semibold text-sm uppercase tracking-wider">
              Latest News
            </span>
            <h2 class="mt-3 text-3xl lg:text-4xl font-bold text-zinc-900">
              Stay Informed
            </h2>
          </div>
          <.link
            navigate={~p"/news"}
            class="mt-4 sm:mt-0 inline-flex items-center text-blue-600 font-semibold hover:text-blue-700 transition"
          >
            View all news <.icon name="hero-arrow-right" class="ml-2 w-5 h-5" />
          </.link>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <%= for post <- @latest_news do %>
            <div id={"post-#{post.id}"} class="flex flex-col rounded">
              <.link
                navigate={~p"/posts/#{post.url_name}"}
                class="w-full hover:opacity-80 transition duration-200 transition-opacity ease-in-out"
              >
                <div class="relative aspect-video">
                  <canvas
                    id={"blur-hash-image-#{post.id}"}
                    src={get_blur_hash(post.featured_image)}
                    class="absolute inset-0 z-0 rounded-lg w-full h-full object-cover"
                    phx-hook="BlurHashCanvas"
                  >
                  </canvas>

                  <img
                    src={featured_image_url(post.featured_image)}
                    id={"image-#{post.id}"}
                    loading="lazy"
                    phx-hook="BlurHashImage"
                    class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out rounded-lg w-full h-full object-cover"
                    alt={
                      if post.featured_image,
                        do:
                          post.featured_image.alt_text || post.featured_image.title || post.title ||
                            "News article image",
                        else: "News article image"
                    }
                  />
                </div>
              </.link>

              <div class="flex flex-col py-3 px-2 space-y-2">
                <div class="space-y-0.5">
                  <p class="font-semibold text-sm text-zinc-600">
                    <%= Timex.format!(post.published_on, "{WDshort}, {Mshort} {D}") %>
                  </p>
                </div>

                <.link
                  navigate={~p"/posts/#{post.url_name}"}
                  class="text-2xl md:text-xl leading-6 font-semibold text-zinc-900 text-pretty"
                >
                  <%= post.title %>
                </.link>

                <p class="text-sm text-pretty text-zinc-600 py-1 line-clamp-3">
                  <%= preview_text_plain(post) %>
                </p>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </section>

    <%!-- Membership Options Section --%>
    <section
      :if={@current_user == nil}
      class="py-16 lg:py-24 bg-gradient-to-br from-blue-600 to-blue-800"
    >
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="text-center max-w-3xl mx-auto mb-12">
          <h2 class="text-3xl lg:text-4xl font-bold text-white">
            Join Our Community Today
          </h2>
          <p class="mt-4 text-lg text-blue-100">
            We offer two membership options to fit your lifestyle.
          </p>
        </div>

        <div class="grid md:grid-cols-2 gap-8 max-w-4xl mx-auto">
          <%!-- Single Membership --%>
          <div class="bg-white rounded-2xl p-8 shadow-xl">
            <h3 class="text-xl font-bold text-zinc-900">Single Membership</h3>
            <div class="mt-4">
              <span class="text-4xl font-bold text-zinc-900">
                <%= Ysc.MoneyHelper.format_money!(
                  Money.new(:USD, Enum.at(Application.get_env(:ysc, :membership_plans), 0).amount)
                ) %>
              </span>
              <span class="text-zinc-500">/year</span>
            </div>
            <p class="mt-4 text-zinc-600">
              Enjoy all the benefits of the YSC for yourself.
            </p>
            <ul class="mt-6 space-y-3">
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check" class="w-5 h-5 text-blue-600 mr-3" /> Access to both cabins
              </li>
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check" class="w-5 h-5 text-blue-600 mr-3" /> Member events
              </li>
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check" class="w-5 h-5 text-blue-600 mr-3" /> Community access
              </li>
            </ul>
          </div>

          <%!-- Family Membership --%>
          <div class="bg-white rounded-2xl p-8 shadow-xl">
            <h3 class="text-xl font-bold text-zinc-900">Family Membership</h3>
            <div class="mt-4">
              <span class="text-4xl font-bold text-zinc-900">
                <%= Ysc.MoneyHelper.format_money!(
                  Money.new(:USD, Enum.at(Application.get_env(:ysc, :membership_plans), 1).amount)
                ) %>
              </span>
              <span class="text-zinc-500">/year</span>
            </div>
            <p class="mt-4 text-zinc-600">
              Share the YSC experience with your loved ones! Covers you, your spouse, and children under 18.
            </p>
            <ul class="mt-6 space-y-3">
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check" class="w-5 h-5 text-blue-600 mr-3" /> Everything in Single
              </li>
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check" class="w-5 h-5 text-blue-600 mr-3" /> Spouse included
              </li>
              <li class="flex items-center text-zinc-700">
                <.icon name="hero-check" class="w-5 h-5 text-blue-600 mr-3" />
                Children under 18 included
              </li>
            </ul>
          </div>
        </div>

        <div class="text-center mt-12">
          <.link
            navigate={~p"/users/register"}
            class="inline-flex items-center px-8 py-4 text-lg font-bold text-blue-600 bg-white rounded-lg hover:bg-blue-50 transition duration-300 shadow-lg hover:shadow-xl"
          >
            Start Your Application <.icon name="hero-arrow-right" class="ml-2 w-5 h-5" />
          </.link>
        </div>
      </div>
    </section>

    <%!-- Newsletter Section --%>
    <section :if={@current_user == nil} class="py-16 lg:py-24">
      <div class="max-w-screen-xl mx-auto px-4">
        <div class="max-w-2xl mx-auto text-center">
          <h2 class="text-3xl lg:text-4xl font-bold text-zinc-900">
            Stay in the Loop
          </h2>
          <p class="mt-4 text-lg text-zinc-600">
            Sign up for our newsletter to receive updates about YSC and all the fun events we're arranging.
          </p>

          <form phx-submit="subscribe_newsletter" class="mt-8">
            <div class="flex flex-col sm:flex-row gap-4 max-w-md mx-auto">
              <input
                type="email"
                id="newsletter-email"
                name="email"
                value={@newsletter_email}
                class="flex-1 px-4 py-3 border border-zinc-300 rounded-lg text-zinc-900 focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                placeholder="Enter your email"
                required
                disabled={@newsletter_submitted}
              />
              <.button :if={!@newsletter_submitted} type="submit" class="px-6 py-3 whitespace-nowrap">
                Subscribe
              </.button>
            </div>
            <p :if={@newsletter_error} class="mt-3 text-sm text-red-600">
              <%= @newsletter_error %>
            </p>
            <div
              :if={@newsletter_submitted}
              class="mt-3 flex items-center justify-center text-emerald-600"
            >
              <.icon name="hero-check-circle" class="w-5 h-5 mr-2" />
              <span>Thank you for subscribing! Check your email to confirm.</span>
            </div>
            <p class="mt-4 text-sm text-zinc-500">
              We don't spam! Read our
              <.link navigate={~p"/privacy-policy"} class="text-blue-600 hover:underline">
                privacy policy
              </.link>
              for more info.
            </p>
          </form>
        </div>
      </div>
    </section>

    <%!-- Logged-in User Dashboard --%>
    <div :if={@current_user != nil} class="bg-white min-h-screen pb-10">
      <%!-- Welcome Header --%>
      <div class="">
        <div class="max-w-screen-xl mx-auto px-4 py-6 lg:py-8">
          <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-6">
            <div>
              <p class="text-zinc-400 text-sm font-medium uppercase tracking-wider mb-2">
                Welcome back
              </p>
              <h1 class="text-3xl lg:text-4xl font-bold">
                <%= String.capitalize(@current_user.first_name) %> <%= String.capitalize(
                  @current_user.last_name
                ) %>
              </h1>
            </div>
          </div>
        </div>
      </div>

      <%!-- Dashboard Content --%>
      <div class="max-w-screen-xl mx-auto px-4">
        <%!-- Quick Stats / Membership Card --%>
        <div class="grid lg:grid-cols-3 gap-6 mb-10">
          <%!-- Membership Status Card --%>
          <div class="lg:col-span-2 bg-white rounded border border-zinc-200 p-6">
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
              <div class="flex items-center gap-3">
                <div class="w-12 h-12 bg-blue-100 rounded flex items-center justify-center">
                  <.icon name="hero-identification" class="w-6 h-6 text-blue-600" />
                </div>
                <div>
                  <h2 class="text-xl font-bold text-zinc-900">Membership Status</h2>
                  <p class="text-sm text-zinc-500">Your current membership plan</p>
                </div>
              </div>
              <.link
                navigate={~p"/users/membership"}
                class="inline-flex items-center px-4 py-2 text-sm font-semibold text-blue-600 hover:text-blue-700 hover:bg-blue-50 rounded-lg transition-colors"
              >
                Manage <.icon name="hero-arrow-right" class="w-4 h-4 ml-1" />
              </.link>
            </div>
            <.membership_status
              current_membership={@current_membership}
              is_sub_account={@is_sub_account || false}
              primary_user={@primary_user}
            />
          </div>

          <%!-- Quick Actions Card --%>
          <div class="bg-white rounded border border-zinc-200 p-6">
            <h3 class="text-lg font-bold text-zinc-900 mb-4">Quick Actions</h3>
            <div class="space-y-3">
              <.link
                navigate={~p"/bookings/tahoe"}
                class="flex items-center p-3 rounded hover:bg-zinc-50 transition-colors group"
              >
                <div class="w-10 h-10 bg-emerald-100 rounded-lg flex items-center justify-center mr-3 group-hover:bg-emerald-200 transition-colors">
                  <.icon name="hero-home" class="w-5 h-5 text-emerald-600" />
                </div>
                <div class="flex-1">
                  <p class="font-semibold text-zinc-900">Lake Tahoe</p>
                  <p class="text-xs text-zinc-500">Book cabin</p>
                </div>
                <.icon name="hero-chevron-right" class="w-5 h-5 text-zinc-400" />
              </.link>
              <.link
                navigate={~p"/bookings/clear-lake"}
                class="flex items-center p-3 rounded hover:bg-zinc-50 transition-colors group"
              >
                <div class="w-10 h-10 bg-sky-100 rounded-lg flex items-center justify-center mr-3 group-hover:bg-sky-200 transition-colors">
                  <.icon name="hero-home" class="w-5 h-5 text-sky-600" />
                </div>
                <div class="flex-1">
                  <p class="font-semibold text-zinc-900">Clear Lake</p>
                  <p class="text-xs text-zinc-500">Book cabin</p>
                </div>
                <.icon name="hero-chevron-right" class="w-5 h-5 text-zinc-400" />
              </.link>
              <.link
                navigate={~p"/users/settings"}
                class="flex items-center p-3 rounded hover:bg-zinc-50 transition-colors group"
              >
                <div class="w-10 h-10 bg-zinc-100 rounded-lg flex items-center justify-center mr-3 group-hover:bg-zinc-200 transition-colors">
                  <.icon name="hero-cog-6-tooth" class="w-5 h-5 text-zinc-600" />
                </div>
                <div class="flex-1">
                  <p class="font-semibold text-zinc-900">Settings</p>
                  <p class="text-xs text-zinc-500">Account preferences</p>
                </div>
                <.icon name="hero-chevron-right" class="w-5 h-5 text-zinc-400" />
              </.link>
              <%= if @current_user && @current_user.role == :admin do %>
                <.link
                  navigate={~p"/expensereport"}
                  class="flex items-center p-3 rounded hover:bg-zinc-50 transition-colors group"
                >
                  <div class="w-10 h-10 bg-orange-100 rounded-lg flex items-center justify-center mr-3 group-hover:bg-orange-200 transition-colors">
                    <.icon name="hero-receipt-refund" class="w-5 h-5 text-orange-600" />
                  </div>
                  <div class="flex-1">
                    <p class="font-semibold text-zinc-900">Expense Report</p>
                    <p class="text-xs text-zinc-500">File expense report</p>
                  </div>
                  <.icon name="hero-chevron-right" class="w-5 h-5 text-zinc-400" />
                </.link>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Bookings and Events Grid --%>
        <div class="grid lg:grid-cols-2 gap-6">
          <%!-- Upcoming Bookings --%>
          <div class="bg-white rounded border border-zinc-200 p-6">
            <div class="flex items-center justify-between mb-6">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 bg-amber-100 rounded flex items-center justify-center">
                  <.icon name="hero-home-modern" class="w-5 h-5 text-amber-600" />
                </div>
                <h2 class="text-xl font-bold text-zinc-900">Upcoming Bookings</h2>
              </div>
              <.link
                navigate={~p"/users/payments"}
                class="text-sm font-semibold text-blue-600 hover:text-blue-700"
              >
                View all →
              </.link>
            </div>

            <div :if={Enum.empty?(@future_bookings)} class="text-center py-8">
              <div class="w-16 h-16 bg-zinc-100 rounded-full flex items-center justify-center mx-auto mb-4">
                <.icon name="hero-home" class="w-8 h-8 text-zinc-400" />
              </div>
              <h3 class="text-lg font-semibold text-zinc-900 mb-2">No upcoming bookings</h3>
              <p class="text-zinc-500 text-sm mb-4">Plan your next cabin getaway</p>
              <.link
                navigate={~p"/bookings/tahoe"}
                class="inline-flex items-center px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white text-sm font-semibold rounded-lg transition-colors"
              >
                Book Now
              </.link>
            </div>

            <div :if={!Enum.empty?(@future_bookings)} class="space-y-4">
              <%= for booking <- @future_bookings do %>
                <.link
                  navigate={~p"/bookings/#{booking.id}/receipt"}
                  class="block p-4 rounded border border-zinc-200 hover:border-blue-300 hover:shadow-md transition-all group"
                >
                  <div class="flex items-start justify-between mb-3">
                    <div>
                      <div class="flex items-center gap-2 mb-1">
                        <span class="font-bold text-zinc-900">
                          <%= format_property_name(booking.property) %>
                        </span>
                        <span class="text-xs px-2 py-0.5 bg-blue-100 text-blue-700 rounded-full font-medium">
                          <%= case days_until_booking(booking) do
                            :started -> "In progress"
                            0 -> "Today"
                            1 -> "Tomorrow"
                            days -> "In #{days} days"
                          end %>
                        </span>
                      </div>
                      <p class="text-xs text-zinc-500"><%= booking.reference_id %></p>
                    </div>
                    <.icon
                      name="hero-arrow-right"
                      class="w-5 h-5 text-zinc-400 group-hover:text-blue-600 transition-colors"
                    />
                  </div>
                  <div class="flex items-center gap-4 text-sm text-zinc-600">
                    <div class="flex items-center">
                      <.icon name="hero-calendar" class="w-4 h-4 mr-1.5 text-zinc-400" />
                      <%= Calendar.strftime(booking.checkin_date, "%b %d") %> - <%= Calendar.strftime(
                        booking.checkout_date,
                        "%b %d"
                      ) %>
                    </div>
                    <%= if booking.booking_mode == :buyout do %>
                      <span class="text-xs px-2 py-0.5 bg-amber-100 text-amber-700 rounded-full">
                        Full Buyout
                      </span>
                    <% end %>
                  </div>
                </.link>
              <% end %>
            </div>
          </div>

          <%!-- Upcoming Events --%>
          <div class="bg-white rounded border border-zinc-200 p-6">
            <div class="flex items-center justify-between mb-6">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 bg-purple-100 rounded flex items-center justify-center">
                  <.icon name="hero-ticket" class="w-5 h-5 text-purple-600" />
                </div>
                <h2 class="text-xl font-bold text-zinc-900">Your Events</h2>
              </div>
              <.link
                navigate={~p"/events"}
                class="text-sm font-semibold text-blue-600 hover:text-blue-700"
              >
                Browse events →
              </.link>
            </div>

            <div :if={Enum.empty?(@upcoming_tickets)} class="text-center py-8">
              <div class="w-16 h-16 bg-zinc-100 rounded-full flex items-center justify-center mx-auto mb-4">
                <.icon name="hero-calendar-days" class="w-8 h-8 text-zinc-400" />
              </div>
              <h3 class="text-lg font-semibold text-zinc-900 mb-2">No upcoming events</h3>
              <p class="text-zinc-500 text-sm mb-4">Discover what's happening in our community</p>
              <.link
                navigate={~p"/events"}
                class="inline-flex items-center px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white text-sm font-semibold rounded-lg transition-colors"
              >
                Browse Events
              </.link>
            </div>

            <div :if={!Enum.empty?(@upcoming_tickets)} class="space-y-4">
              <%= for {event, grouped_tiers} <- group_tickets_by_event_and_tier(@upcoming_tickets) do %>
                <div class="p-4 rounded-xl border border-zinc-200">
                  <.link navigate={~p"/events/#{event.id}"} class="block group">
                    <div class="flex items-start justify-between mb-3">
                      <div class="flex-1 min-w-0">
                        <h3 class="font-bold text-zinc-900 group-hover:text-blue-600 transition-colors truncate">
                          <%= event.title %>
                        </h3>
                        <div class="flex items-center gap-2 mt-1">
                          <span class="text-xs px-2 py-0.5 bg-purple-100 text-purple-700 rounded-full font-medium">
                            <%= case days_until_event(event) do
                              0 -> "Today"
                              1 -> "Tomorrow"
                              days -> "In #{days} days"
                            end %>
                          </span>
                        </div>
                      </div>
                      <.icon
                        name="hero-arrow-right"
                        class="w-5 h-5 text-zinc-400 group-hover:text-blue-600 transition-colors flex-shrink-0 ml-2"
                      />
                    </div>
                  </.link>
                  <div class="flex items-center gap-4 text-sm text-zinc-600 mb-3">
                    <div class="flex items-center">
                      <.icon name="hero-calendar" class="w-4 h-4 mr-1.5 text-zinc-400" />
                      <%= Calendar.strftime(event.start_date, "%b %d, %Y") %>
                    </div>
                    <div :if={event.location_name} class="flex items-center truncate">
                      <.icon name="hero-map-pin" class="w-4 h-4 mr-1.5 text-zinc-400 flex-shrink-0" />
                      <span class="truncate"><%= event.location_name %></span>
                    </div>
                  </div>
                  <%!-- Tickets Summary --%>
                  <div class="flex flex-wrap gap-2">
                    <%= for {tier_name, tickets} <- grouped_tiers do %>
                      <span class="inline-flex items-center px-2.5 py-1 bg-green-50 text-green-700 text-xs font-medium rounded-full border border-green-200">
                        <.icon name="hero-ticket" class="w-3.5 h-3.5 mr-1" />
                        <%= length(tickets) %>× <%= tier_name %>
                      </span>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Community Events and News --%>
        <div class="mt-12 space-y-8">
          <%!-- Upcoming Events --%>
          <div>
            <div class="flex items-center justify-between mb-6">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                  <.icon name="hero-calendar-days" class="w-5 h-5 text-blue-600" />
                </div>
                <h2 class="text-xl font-bold text-zinc-900">Upcoming Events</h2>
              </div>
              <.link
                navigate={~p"/events"}
                class="text-sm font-semibold text-blue-600 hover:text-blue-700 transition-colors"
              >
                View all events →
              </.link>
            </div>

            <div
              :if={Enum.empty?(@upcoming_events)}
              class="bg-white rounded-lg p-8 text-center border border-zinc-200"
            >
              <div class="w-12 h-12 bg-zinc-100 rounded-full flex items-center justify-center mx-auto mb-3">
                <.icon name="hero-calendar" class="w-6 h-6 text-zinc-400" />
              </div>
              <h3 class="text-sm font-semibold text-zinc-900 mb-1">No upcoming events</h3>
              <p class="text-xs text-zinc-500">Check back later for new community events</p>
            </div>

            <div
              :if={!Enum.empty?(@upcoming_events)}
              class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6"
            >
              <%= for event <- Enum.take(@upcoming_events, 3) do %>
                <div class={[
                  "flex flex-col rounded",
                  event.state == :cancelled && "opacity-70"
                ]}>
                  <.link
                    navigate={~p"/events/#{event.id}"}
                    class="w-full hover:opacity-80 transition duration-200 transition-opacity ease-in-out"
                  >
                    <.live_component
                      id={"dashboard-event-cover-#{event.id}"}
                      module={YscWeb.Components.Image}
                      image_id={event.image_id}
                      image={Map.get(event, :image)}
                    />
                  </.link>

                  <div class="flex flex-col py-3 px-2 space-y-2">
                    <div>
                      <.event_badge
                        event={event}
                        sold_out={event_sold_out?(event)}
                        selling_fast={Map.get(event, :selling_fast, false)}
                      />
                    </div>

                    <.link
                      navigate={~p"/events/#{event.id}"}
                      class="text-2xl md:text-xl leading-6 font-semibold text-zinc-900 text-pretty"
                    >
                      <%= event.title %>
                    </.link>

                    <div class="space-y-0.5">
                      <p class="font-semibold text-sm text-zinc-800">
                        <%= Timex.format!(event.start_date, "{WDshort}, {Mshort} {D}") %><span :if={
                          event.start_time != nil && event.start_time != ""
                        }>
                        • <%= format_start_time(event.start_time) %>
                      </span>
                      </p>

                      <p
                        :if={event.location_name != nil && event.location_name != ""}
                        class="text-zinc-800 text-sm"
                      >
                        <%= event.location_name %>
                      </p>
                    </div>

                    <p class="text-sm text-pretty text-zinc-600 py-1"><%= event.description %></p>

                    <div
                      :if={event.state != :cancelled}
                      class="flex flex-row space-x-2 pt-2 items-center"
                    >
                      <p class={[
                        "text-sm font-semibold",
                        if event_sold_out?(event) do
                          "text-zinc-800 line-through"
                        else
                          "text-zinc-800"
                        end
                      ]}>
                        <%= event.pricing_info.display_text %>
                      </p>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Latest News --%>
          <div>
            <div class="flex items-center justify-between mb-6">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 bg-emerald-100 rounded-lg flex items-center justify-center">
                  <.icon name="hero-newspaper" class="w-5 h-5 text-emerald-600" />
                </div>
                <h2 class="text-xl font-bold text-zinc-900">Latest Club News</h2>
              </div>
              <.link
                navigate={~p"/news"}
                class="text-sm font-semibold text-blue-600 hover:text-blue-700 transition-colors"
              >
                View all news →
              </.link>
            </div>

            <div
              :if={Enum.empty?(@latest_news)}
              class="bg-white rounded-lg p-8 text-center border border-zinc-200"
            >
              <div class="w-12 h-12 bg-zinc-100 rounded-full flex items-center justify-center mx-auto mb-3">
                <.icon name="hero-document-text" class="w-6 h-6 text-zinc-400" />
              </div>
              <h3 class="text-sm font-semibold text-zinc-900 mb-1">No news available</h3>
              <p class="text-xs text-zinc-500">Check back later for club updates</p>
            </div>

            <div
              :if={!Enum.empty?(@latest_news)}
              class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6"
            >
              <%= for post <- Enum.take(@latest_news, 3) do %>
                <div id={"dashboard-post-#{post.id}"} class="flex flex-col rounded">
                  <.link
                    navigate={~p"/posts/#{post.url_name}"}
                    class="w-full hover:opacity-80 transition duration-200 transition-opacity ease-in-out"
                  >
                    <div class="relative aspect-video">
                      <canvas
                        id={"blur-hash-image-dashboard-#{post.id}"}
                        src={get_blur_hash(post.featured_image)}
                        class="absolute inset-0 z-0 rounded-lg w-full h-full object-cover"
                        phx-hook="BlurHashCanvas"
                      >
                      </canvas>

                      <img
                        src={featured_image_url(post.featured_image)}
                        id={"image-dashboard-#{post.id}"}
                        loading="lazy"
                        phx-hook="BlurHashImage"
                        class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out rounded-lg w-full h-full object-cover"
                        alt={
                          if post.featured_image,
                            do:
                              post.featured_image.alt_text || post.featured_image.title || post.title ||
                                "News article image",
                            else: "News article image"
                        }
                      />
                    </div>
                  </.link>

                  <div class="flex flex-col py-3 px-2 space-y-2">
                    <div class="space-y-0.5">
                      <p class="font-semibold text-sm text-zinc-600">
                        <%= Timex.format!(post.published_on, "{WDshort}, {Mshort} {D}") %>
                      </p>
                    </div>

                    <.link
                      navigate={~p"/posts/#{post.url_name}"}
                      class="text-2xl md:text-xl leading-6 font-semibold text-zinc-900 text-pretty"
                    >
                      <%= post.title %>
                    </.link>

                    <p class="text-sm text-pretty text-zinc-600 py-1 line-clamp-3">
                      <%= preview_text_plain(post) %>
                    </p>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp get_current_membership(user) do
    # For sub-accounts, check the primary user's membership
    user_to_check =
      if Accounts.is_sub_account?(user) do
        Accounts.get_primary_user(user) || user
      else
        user
      end

    # Check for lifetime membership first
    if Accounts.has_lifetime_membership?(user_to_check) do
      lifetime_plan =
        Application.get_env(:ysc, :membership_plans)
        |> Enum.find(&(&1.id == :lifetime))

      %{
        plan: lifetime_plan,
        type: :lifetime,
        awarded_at: user_to_check.lifetime_membership_awarded_at,
        renewal_date: nil
      }
    else
      # Get active subscriptions
      # If subscriptions aren't preloaded, fetch them
      subscriptions =
        case user_to_check.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            Ysc.Customers.subscriptions(user_to_check)
            |> Enum.filter(fn sub ->
              Subscriptions.valid?(sub) and sub.stripe_status == "active"
            end)

          subscriptions when is_list(subscriptions) ->
            subscriptions
            |> Enum.filter(fn sub ->
              Subscriptions.valid?(sub) and sub.stripe_status == "active"
            end)

          _ ->
            []
        end

      case subscriptions do
        [] ->
          nil

        [subscription | _] ->
          # Preload subscription items if needed
          subscription =
            case subscription.subscription_items do
              %Ecto.Association.NotLoaded{} ->
                Ysc.Repo.preload(subscription, :subscription_items)

              _ ->
                subscription
            end

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

  defp format_start_time(time) when is_binary(time) do
    format_start_time(Timex.parse!(time, "{h12}:{m} {AM}"))
  end

  defp format_start_time(time) do
    Timex.format!(time, "{h12}:{m} {AM}")
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

  # Helper functions for news posts
  defp preview_text_plain(%Post{preview_text: nil} = post) do
    Scrubber.scrub(post.raw_body, YscWeb.Scrubber.StripEverythingExceptText)
    |> String.replace(~r/<[^>]*>/, "")
    |> String.trim()
  end

  defp preview_text_plain(post) do
    post.preview_text
    |> String.replace(~r/<[^>]*>/, "")
    |> String.trim()
  end

  defp get_blur_hash(nil), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash

  defp featured_image_url(nil), do: "/images/ysc_logo.png"
  defp featured_image_url(%Image{optimized_image_path: nil} = image), do: image.raw_image_path
  defp featured_image_url(%Image{optimized_image_path: optimized_path}), do: optimized_path
end
