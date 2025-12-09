defmodule YscWeb.HomeLive do
  use YscWeb, :live_view

  alias Ysc.{Accounts, Events, Subscriptions, Mailpoet}
  alias Ysc.Bookings.{Booking, Season}
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
        upcoming_events = Events.list_upcoming_events(3)

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
            <span class="inline-block ml-2 transition-transform group-hover:translate-x-1">→</span>
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
              Ski in winter, hike in summer, and relax year-round at our beautiful Lake Tahoe retreat. The cabin offers stunning mountain views and is perfectly positioned for all your alpine adventures.
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
              Swim, boat, and unwind at our peaceful lakeside cabin. Clear Lake offers the perfect escape for water lovers and those seeking tranquility away from the city.
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

        <div class="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
          <%= for event <- @upcoming_events do %>
            <.link
              navigate={~p"/events/#{event.id}"}
              class="group bg-zinc-800 rounded-2xl overflow-hidden hover:bg-zinc-750 transition-all hover:scale-[1.02] hover:shadow-2xl"
            >
              <div class="aspect-[16/10] bg-zinc-700 relative overflow-hidden">
                <img
                  :if={event.image}
                  src={event.image.optimized_image_path}
                  alt={event.title}
                  class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
                />
                <div
                  :if={!event.image}
                  class="w-full h-full flex items-center justify-center bg-gradient-to-br from-blue-600 to-blue-800"
                >
                  <.icon name="hero-calendar-days" class="w-16 h-16 text-white/50" />
                </div>
                <div class="absolute top-4 left-4 bg-white rounded-lg px-3 py-2 text-center shadow-lg">
                  <div class="text-xs font-semibold text-zinc-500 uppercase">
                    <%= Calendar.strftime(event.start_date, "%b") %>
                  </div>
                  <div class="text-2xl font-bold text-zinc-900 leading-none">
                    <%= Calendar.strftime(event.start_date, "%d") %>
                  </div>
                </div>
              </div>
              <div class="p-6">
                <h3 class="text-xl font-bold text-white group-hover:text-blue-400 transition-colors line-clamp-2">
                  <%= event.title %>
                </h3>
                <div class="mt-3 flex items-center text-zinc-400 text-sm">
                  <.icon name="hero-clock" class="w-4 h-4 mr-2" />
                  <%= Calendar.strftime(event.start_date, "%A, %B %d at %I:%M %p") %>
                </div>
                <div :if={event.location_name} class="mt-2 flex items-center text-zinc-400 text-sm">
                  <.icon name="hero-map-pin" class="w-4 h-4 mr-2" />
                  <%= event.location_name %>
                </div>
              </div>
            </.link>
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
    <div :if={@current_user != nil} class="bg-white min-h-screen">
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
          <div class="lg:col-span-2 bg-white rounded shadow-sm border border-zinc-200 p-6">
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
            <.membership_status current_membership={@current_membership} />
          </div>

          <%!-- Quick Actions Card --%>
          <div class="bg-white rounded shadow-sm border border-zinc-200 p-6">
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
            </div>
          </div>
        </div>

        <%!-- Bookings and Events Grid --%>
        <div class="grid lg:grid-cols-2 gap-6">
          <%!-- Upcoming Bookings --%>
          <div class="bg-white rounded shadow-sm border border-zinc-200 p-6">
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
                  navigate={~p"/bookings/#{booking.id}"}
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
          <div class="bg-white rounded shadow-sm border border-zinc-200 p-6">
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
