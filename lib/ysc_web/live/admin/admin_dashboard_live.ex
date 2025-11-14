defmodule YscWeb.AdminDashboardLive do
  use YscWeb, :live_view

  alias Ysc.{Posts, Events, Accounts}

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
      <h1 class="text-2xl font-semibold leading-8 text-zinc-800 py-6">
        Overview
      </h1>

      <div class="mb-6">
        <.live_component module={YscWeb.AdminSearchComponent} id="admin-search" />
      </div>

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <!-- Latest Comments Module -->
        <div class="bg-white rounded border p-6">
          <div class="flex justify-between items-center mb-4">
            <h2 class="text-xl font-semibold text-zinc-800">Latest Comments</h2>
            <.link
              navigate={~p"/admin/posts"}
              class="text-sm text-blue-600 hover:underline font-medium"
            >
              View all posts
            </.link>
          </div>
          <div :if={Enum.empty?(@latest_comments)} class="text-sm text-zinc-500 py-4">
            No comments yet
          </div>
          <ul :if={not Enum.empty?(@latest_comments)} class="space-y-4">
            <li :for={comment <- @latest_comments} class="border-b border-zinc-200 pb-4 last:border-0">
              <div class="flex justify-between items-start mb-2">
                <div class="flex-1">
                  <.link
                    navigate={~p"/posts/#{comment.post.url_name || comment.post.id}"}
                    class="text-sm font-semibold text-zinc-800 hover:text-blue-600"
                  >
                    <%= comment.post.title %>
                  </.link>
                  <p class="text-sm text-zinc-600 mt-1 line-clamp-2">
                    <%= comment.text %>
                  </p>
                </div>
              </div>
              <div class="flex items-center justify-between text-xs text-zinc-500 mt-2">
                <span>
                  By
                  <span class="font-medium text-zinc-700">
                    <%= "#{comment.author.first_name} #{comment.author.last_name}" %>
                  </span>
                </span>
                <span>
                  <%= Timex.format!(comment.inserted_at, "{YYYY}-{0M}-{0D} {h12}:{m} {AM}") %>
                </span>
              </div>
            </li>
          </ul>
        </div>
        <!-- Ticket Registrations Module -->
        <div class="bg-white rounded border p-6">
          <div class="flex justify-between items-center mb-4">
            <h2 class="text-xl font-semibold text-zinc-800">Event Ticket Sales</h2>
            <.link
              navigate={~p"/admin/events"}
              class="text-sm text-blue-600 hover:underline font-medium"
            >
              View all events
            </.link>
          </div>
          <div :if={Enum.empty?(@events_with_tickets)} class="text-sm text-zinc-500 py-4">
            No upcoming events
          </div>
          <div :if={not Enum.empty?(@events_with_tickets)} class="space-y-6">
            <div
              :for={%{event: event, ticket_tiers: tiers} <- @events_with_tickets}
              class="border-b border-zinc-200 pb-4 last:border-0"
            >
              <div class="flex items-center justify-between mb-3">
                <.link
                  navigate={~p"/events/#{event.id}"}
                  class="font-semibold text-zinc-800 hover:text-blue-600"
                >
                  <%= event.title %>
                </.link>
                <.link
                  navigate={~p"/admin/events/#{event.id}/edit"}
                  class="text-sm text-blue-600 hover:text-blue-800 font-medium hover:underline"
                >
                  Edit
                </.link>
              </div>
              <div :if={Enum.empty?(tiers)} class="text-xs text-zinc-500">
                No ticket tiers configured
              </div>
              <div :if={not Enum.empty?(tiers)} class="space-y-2">
                <div
                  :for={tier <- tiers}
                  class="flex justify-between items-center text-sm bg-zinc-50 rounded px-3 py-2"
                >
                  <div class="flex-1">
                    <span class="font-medium text-zinc-800"><%= tier.name %></span>
                    <span :if={tier.quantity} class="text-zinc-500 ml-2">
                      / <%= tier.quantity %> available
                    </span>
                    <span :if={is_nil(tier.quantity)} class="text-zinc-500 ml-2">
                      (unlimited)
                    </span>
                  </div>
                  <span class="font-semibold text-zinc-800">
                    <%= tier.sold_tickets_count %> sold
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
        <!-- Pending Approval Users Module -->
        <div class="bg-white rounded border p-6 lg:col-span-2">
          <div class="flex justify-between items-center mb-4">
            <h2 class="text-xl font-semibold text-zinc-800">Pending Application Reviews</h2>
            <.link
              navigate={~p"/admin/users"}
              class="text-sm text-blue-600 hover:underline font-medium"
            >
              View all users
            </.link>
          </div>
          <div :if={Enum.empty?(@pending_users)} class="text-sm text-zinc-500 py-4">
            No pending applications
          </div>
          <div :if={not Enum.empty?(@pending_users)} class="overflow-x-auto">
            <table class="min-w-full divide-y divide-zinc-200">
              <thead class="bg-zinc-50">
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-semibold text-zinc-700 uppercase tracking-wider">
                    Name
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-semibold text-zinc-700 uppercase tracking-wider">
                    Email
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-semibold text-zinc-700 uppercase tracking-wider">
                    Submitted
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-semibold text-zinc-700 uppercase tracking-wider">
                    Action
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-zinc-200">
                <tr :for={user <- @pending_users} class="hover:bg-zinc-50">
                  <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-800">
                    <%= "#{user.first_name} #{user.last_name}" %>
                  </td>
                  <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                    <%= user.email %>
                  </td>
                  <td class="px-4 py-3 whitespace-nowrap text-sm text-zinc-600">
                    <span :if={user.registration_form && user.registration_form.completed}>
                      <%= Timex.format!(
                        Timex.Timezone.convert(
                          user.registration_form.completed,
                          "America/Los_Angeles"
                        ),
                        "{YYYY}-{0M}-{0D}"
                      ) %>
                      <span class="text-zinc-400 ml-1">
                        (<%= Timex.from_now(user.registration_form.completed) %>)
                      </span>
                    </span>
                    <span
                      :if={!user.registration_form || !user.registration_form.completed}
                      class="text-zinc-400"
                    >
                      Not available
                    </span>
                  </td>
                  <td class="px-4 py-3 whitespace-nowrap text-right text-sm">
                    <.link
                      navigate={~p"/admin/users/#{user.id}/review"}
                      class="text-blue-600 hover:text-blue-800 font-semibold hover:underline"
                    >
                      Review
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </.side_menu>
    """
  end

  @spec mount(any(), any(), map()) :: {:ok, map()}
  def mount(_params, _session, socket) do
    latest_comments = Posts.get_latest_comments(5)
    events_with_tickets = Events.get_upcoming_events_with_ticket_tier_counts()
    pending_users = Accounts.get_pending_approval_users()

    {:ok,
     socket
     |> assign(:active_page, :dashboard)
     |> assign(:page_title, "Dashboard")
     |> assign(:latest_comments, latest_comments)
     |> assign(:events_with_tickets, events_with_tickets)
     |> assign(:pending_users, pending_users)}
  end
end
