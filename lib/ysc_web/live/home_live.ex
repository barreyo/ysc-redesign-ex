defmodule YscWeb.HomeLive do
  use YscWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Home")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
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

            <form class="py-2">
              <input
                class="px-3 py-2 block w-full border rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 border-zinc-300 focus:border-zinc-400 mb-4"
                name="email"
                label="Email"
                placeholder="Email address"
              />
              <.button>Let's keep in touch</.button>
              <p class="not-prose text-sm italic text-zinc-500">
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
          <div class="space-y-8">
            <!-- Welcome Section -->
            <div>
              <h1 class="text-3xl font-bold text-zinc-900 mb-2">
                Welcome back, <%= String.capitalize(@current_user.first_name) %>!
              </h1>
              <p class="text-zinc-600">Ready for your next Scandinavian adventure?</p>
            </div>

            <!-- Quick Actions -->
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
              <.link
                navigate={~p"/users/membership"}
                class="flex items-center p-4 bg-blue-50 rounded-lg border border-blue-200 hover:bg-blue-100 transition-colors"
              >
                <div class="flex-shrink-0">
                  <.icon name="hero-heart" class="w-8 h-8 text-blue-600" />
                </div>
                <div class="ml-3">
                  <h3 class="text-sm font-medium text-blue-900">Membership</h3>
                  <p class="text-sm text-blue-700">Manage your membership</p>
                </div>
              </.link>

              <.link
                navigate={~p"/events"}
                class="flex items-center p-4 bg-green-50 rounded-lg border border-green-200 hover:bg-green-100 transition-colors"
              >
                <div class="flex-shrink-0">
                  <.icon name="hero-calendar-days" class="w-8 h-8 text-green-600" />
                </div>
                <div class="ml-3">
                  <h3 class="text-sm font-medium text-green-900">Events</h3>
                  <p class="text-sm text-green-700">Browse upcoming events</p>
                </div>
              </.link>

              <.link
                href="#"
                class="flex items-center p-4 bg-orange-50 rounded-lg border border-orange-200 hover:bg-orange-100 transition-colors"
              >
                <div class="flex-shrink-0">
                  <.icon name="hero-ticket" class="w-8 h-8 text-orange-600" />
                </div>
                <div class="ml-3">
                  <h3 class="text-sm font-medium text-orange-900">My Tickets</h3>
                  <p class="text-sm text-orange-700">View your event tickets</p>
                </div>
              </.link>

              <.link
                navigate={~p"/users/settings"}
                class="flex items-center p-4 bg-purple-50 rounded-lg border border-purple-200 hover:bg-purple-100 transition-colors"
              >
                <div class="flex-shrink-0">
                  <.icon name="hero-user" class="w-8 h-8 text-purple-600" />
                </div>
                <div class="ml-3">
                  <h3 class="text-sm font-medium text-purple-900">Profile</h3>
                  <p class="text-sm text-purple-700">Update your information</p>
                </div>
              </.link>
            </div>

            <!-- My Events Section -->
            <div class="bg-white rounded-lg border border-zinc-200 p-6">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-xl font-semibold text-zinc-900">My Upcoming Events</h2>
                <.link
                  navigate={~p"/events"}
                  class="text-blue-600 hover:text-blue-800 text-sm font-medium"
                >
                  Browse all events →
                </.link>
              </div>

              <!-- User's events with tickets will be loaded here via LiveView component -->
              <.live_component
                id="home-user-events-list"
                module={YscWeb.UserEventsListLive}
                current_user={@current_user}
              />
            </div>

            <!-- Upcoming Events Section -->
            <div class="bg-white rounded-lg border border-zinc-200 p-6">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-xl font-semibold text-zinc-900">All Upcoming Events</h2>
                <.link
                  navigate={~p"/events"}
                  class="text-blue-600 hover:text-blue-800 text-sm font-medium"
                >
                  View all events →
                </.link>
              </div>

              <!-- Events will be loaded here via LiveView component -->
              <.live_component
                id="home-events-list"
                module={YscWeb.EventsListLive}
              />
            </div>

            <!-- Latest News Section -->
            <div class="bg-white rounded-lg border border-zinc-200 p-6">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-xl font-semibold text-zinc-900">Latest News</h2>
                <.link
                  navigate={~p"/news"}
                  class="text-blue-600 hover:text-blue-800 text-sm font-medium"
                >
                  Read more news →
                </.link>
              </div>

              <!-- News will be loaded here via LiveView component -->
              <.live_component
                id="home-news-list"
                module={YscWeb.NewsListLive}
              />
            </div>

            <!-- Club Resources -->
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <!-- Cabin Information -->
              <div class="bg-white rounded-lg border border-zinc-200 p-6">
                <h3 class="text-lg font-semibold text-zinc-900 mb-3">Club Cabins</h3>
                <div class="space-y-3">
                  <div class="flex items-start">
                    <div class="flex-shrink-0">
                      <.icon name="hero-home" class="w-5 h-5 text-blue-600 mt-0.5" />
                    </div>
                    <div class="ml-3">
                      <h4 class="text-sm font-medium text-zinc-900">Clear Lake Cabin</h4>
                      <p class="text-sm text-zinc-600">Perfect for summer getaways and lake activities</p>
                    </div>
                  </div>
                  <div class="flex items-start">
                    <div class="flex-shrink-0">
                      <.icon name="hero-mountain" class="w-5 h-5 text-green-600 mt-0.5" />
                    </div>
                    <div class="ml-3">
                      <h4 class="text-sm font-medium text-zinc-900">Lake Tahoe Cabin</h4>
                      <p class="text-sm text-zinc-600">Year-round mountain adventures and skiing</p>
                    </div>
                  </div>
                </div>
                <div class="mt-4">
                  <.link
                    href="#"
                    class="text-blue-600 hover:text-blue-800 text-sm font-medium"
                  >
                    Learn about cabin bookings →
                  </.link>
                </div>
              </div>

              <!-- Quick Links -->
              <div class="bg-white rounded-lg border border-zinc-200 p-6">
                <h3 class="text-lg font-semibold text-zinc-900 mb-3">Quick Links</h3>
                <div class="space-y-2">
                  <.link
                    navigate={~p"/volunteer"}
                    class="flex items-center text-sm text-zinc-600 hover:text-zinc-900"
                  >
                    <.icon name="hero-hand-raised" class="w-4 h-4 mr-2" />
                    Volunteer Opportunities
                  </.link>
                  <.link
                    navigate={~p"/contact"}
                    class="flex items-center text-sm text-zinc-600 hover:text-zinc-900"
                  >
                    <.icon name="hero-envelope" class="w-4 h-4 mr-2" />
                    Contact the Board
                  </.link>
                  <.link
                    navigate={~p"/board"}
                    class="flex items-center text-sm text-zinc-600 hover:text-zinc-900"
                  >
                    <.icon name="hero-users" class="w-4 h-4 mr-2" />
                    Meet the Board
                  </.link>
                  <.link
                    navigate={~p"/code-of-conduct"}
                    class="flex items-center text-sm text-zinc-600 hover:text-zinc-900"
                  >
                    <.icon name="hero-shield-check" class="w-4 h-4 mr-2" />
                    Code of Conduct
                  </.link>
                </div>
              </div>
            </div>

            <!-- Membership Status (if applicable) -->
            <div :if={@current_user.state == :active} class="bg-green-50 rounded-lg border border-green-200 p-6">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <.icon name="hero-check-circle" class="w-8 h-8 text-green-600" />
                </div>
                <div class="ml-3">
                  <h3 class="text-lg font-medium text-green-900">Active Member</h3>
                  <p class="text-sm text-green-700">
                    You're all set to enjoy all YSC benefits and events!
                  </p>
                </div>
              </div>
            </div>

            <!-- Pending Approval Message -->
            <div :if={@current_user.state == :pending_approval} class="bg-yellow-50 rounded-lg border border-yellow-200 p-6">
              <div class="flex items-center">
                <div class="flex-shrink-0">
                  <.icon name="hero-clock" class="w-8 h-8 text-yellow-600" />
                </div>
                <div class="ml-3">
                  <h3 class="text-lg font-medium text-yellow-900">Application Under Review</h3>
                  <p class="text-sm text-yellow-700">
                    Your membership application is being reviewed. You'll receive an email once it's approved.
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
