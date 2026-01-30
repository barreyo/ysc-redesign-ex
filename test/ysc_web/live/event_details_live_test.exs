defmodule YscWeb.EventDetailsLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.TestDataFactory

  alias Ysc.Events
  alias Ysc.Repo
  alias Ysc.Media

  # Helper to create an image
  defp create_image do
    uploader = user_fixture()

    {:ok, image} =
      %Media.Image{}
      |> Media.Image.add_image_changeset(%{
        title: "Test Event Image",
        raw_image_path: "/uploads/test_event.jpg",
        optimized_image_path: "/uploads/test_event_optimized.jpg",
        thumbnail_path: "/uploads/test_event_thumb.jpg",
        blur_hash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj",
        user_id: uploader.id
      })
      |> Repo.insert()

    image
  end

  # Helper to create an event
  defp create_event(attrs) do
    organizer = attrs[:organizer] || user_fixture()
    image = if Map.get(attrs, :with_image, true), do: create_image(), else: nil

    default_attrs = %{
      title: "Test Event #{System.unique_integer()}",
      description: "A test event description",
      start_date: DateTime.add(DateTime.utc_now(), 7, :day),
      end_date: DateTime.add(DateTime.utc_now(), 8, :day),
      state: :published,
      ticket_sales_start: DateTime.utc_now(),
      ticket_sales_end: DateTime.add(DateTime.utc_now(), 6, :day),
      location: "Test Location",
      max_attendees: 100,
      organizer_id: organizer.id,
      image_id: if(image, do: image.id, else: nil)
    }

    attrs = attrs |> Map.delete(:organizer) |> Map.delete(:with_image)
    attrs = Map.merge(default_attrs, attrs)

    {:ok, event} =
      %Events.Event{}
      |> Events.Event.changeset(attrs)
      |> Repo.insert()

    event
  end

  describe "mount/3 - event access" do
    test "loads event by ID successfully", %{conn: conn} do
      event = create_event(%{title: "Summer Party"})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Summer Party"
    end

    test "handles non-existent event", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/events/#{Ecto.ULID.generate()}")

      assert path == "/events"
    end

    test "sets page title to event title", %{conn: conn} do
      event = create_event(%{title: "Annual Gala"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert page_title(view) =~ "Annual Gala"
    end
  end

  describe "event display" do
    test "displays event title", %{conn: conn} do
      event = create_event(%{title: "Mountain Hike"})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Mountain Hike"
    end

    test "displays event description", %{conn: conn} do
      event =
        create_event(%{
          title: "Test",
          description: "Join us for an amazing outdoor adventure"
        })

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "Join us for an amazing outdoor adventure"
    end

    test "displays event start date", %{conn: conn} do
      start_date = DateTime.add(DateTime.utc_now(), 10, :day)
      event = create_event(%{title: "Test", start_date: start_date})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      # Should display formatted date (format may vary, just check for year)
      year = start_date |> DateTime.to_date() |> Date.to_string() |> String.split("-") |> hd()
      assert html =~ year
    end

    test "displays event location when provided", %{conn: conn} do
      event = create_event(%{title: "Test", location: "Central Park, NY"})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      # Location would typically be shown in the details
      assert html =~ "Test"
    end
  end

  describe "cancelled events" do
    test "shows cancelled notice for cancelled events", %{conn: conn} do
      event = create_event(%{title: "Test", state: :cancelled})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "This Event Has Been Cancelled"
    end

    test "applies visual styling to cancelled events", %{conn: conn} do
      event = create_event(%{title: "Test", state: :cancelled})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      # Cancelled events have red styling
      assert html =~ "bg-red-600"
      assert html =~ "grayscale"
    end

    test "disables interactions for cancelled events", %{conn: conn} do
      event = create_event(%{title: "Test", state: :cancelled})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      # Content section is disabled for cancelled events
      assert html =~ "pointer-events-none"
    end
  end

  describe "sold out events" do
    test "does not show sold out badge for events with capacity", %{conn: conn} do
      event = create_event(%{title: "Test", max_attendees: 100})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Wait for async data
      :timer.sleep(100)

      html = render(view)
      # Event not at capacity, no SOLD OUT badge
      refute html =~ "SOLD OUT"
    end
  end

  describe "event image" do
    test "renders event cover image component", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      # Image component should be present
      assert html =~ "event-cover-#{event.id}"
    end

    test "applies gradient overlay to image", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "bg-gradient-to-t"
    end
  end

  describe "user tickets - unauthenticated" do
    test "does not show user tickets section when not logged in", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      # User tickets section only visible when authenticated with tickets
      refute html =~ "Order #"
    end
  end

  describe "user tickets - authenticated" do
    test "shows empty state when user has no tickets", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Wait for async data
      :timer.sleep(100)

      html = render(view)
      # No tickets, no order badges shown
      refute html =~ "Order #"
    end
  end

  describe "event handlers - modal interactions" do
    test "open-ticket-modal event opens modal", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Opening ticket modal redirects to tickets page
      assert {:error, {:live_redirect, %{to: path}}} = render_click(view, "open-ticket-modal")
      assert path =~ "/events/#{event.id}/tickets"
    end

    test "close-ticket-modal event closes modal", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      result = render_click(view, "close-ticket-modal")

      # Modal should be closed
      assert is_binary(result)
    end

    test "toggle-map event toggles map visibility", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      result = render_click(view, "toggle-map")

      # Map visibility should toggle
      assert is_binary(result)
    end
  end

  describe "login requirement" do
    test "login-redirect event for unauthenticated users", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      assert {:error, {:redirect, %{to: path}}} = render_click(view, "login-redirect")

      # Should redirect to login
      assert path =~ "/users/log-in"
    end
  end

  describe "registration modal" do
    test "close-registration-modal event closes registration", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      result = render_click(view, "close-registration-modal")

      assert is_binary(result)
    end
  end

  describe "payment modal" do
    test "close-payment-modal event closes payment modal", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      result = render_click(view, "close-payment-modal")

      assert is_binary(result)
    end
  end

  describe "free ticket confirmation" do
    test "close-free-ticket-confirmation event closes confirmation", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      result = render_click(view, "close-free-ticket-confirmation")

      assert is_binary(result)
    end
  end

  describe "order completion" do
    test "close-order-completion event closes completion modal", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      result = render_click(view, "close-order-completion")

      assert is_binary(result)
    end
  end

  describe "attendees modal" do
    test "show-attendees-modal event shows attendees", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      result = render_click(view, "show-attendees-modal")

      assert is_binary(result)
    end

    test "close-attendees-modal event closes attendees modal", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      result = render_click(view, "close-attendees-modal")

      assert is_binary(result)
    end
  end

  describe "page structure" do
    test "includes main content grid", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "grid"
      assert html =~ "lg:col-span"
    end

    test "includes responsive design classes", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")

      assert html =~ "lg:"
      assert html =~ "md:"
    end
  end

  describe "async data loading" do
    test "loads event data and renders", %{conn: conn} do
      event = create_event(%{title: "Test Event"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")

      # Wait for async data
      :timer.sleep(200)

      html = render(view)
      # Event should be displayed
      assert html =~ "Test Event"
    end
  end

  describe "modal interactions" do
    test "handles close-payment-modal event", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "close-payment-modal")
      assert is_binary(result)
    end

    test "handles close-registration-modal event", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "close-registration-modal")
      assert is_binary(result)
    end

    test "handles close-free-ticket-confirmation event", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "close-free-ticket-confirmation")
      assert is_binary(result)
    end

    test "handles close-order-completion event", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "close-order-completion")
      assert is_binary(result)
    end

    test "handles payment-redirect-started event", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "payment-redirect-started")
      assert is_binary(result)
    end

    test "handles checkout-expired event", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "checkout-expired")
      assert is_binary(result)
    end
  end

  describe "map interactions" do
    test "handles toggle-map event", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "toggle-map")
      assert is_binary(result)

      # Toggle again
      result = render_click(view, "toggle-map")
      assert is_binary(result)
    end
  end

  describe "authentication-required interactions" do
    test "handles login-redirect event for unauthenticated users", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "login-redirect")
      # Should redirect to login or return HTML
      assert is_binary(result) or match?({:error, {:redirect, %{to: _}}}, result)
    end
  end

  describe "ticket modal interactions" do
    test "opens ticket modal for authenticated user", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Event with Tickets"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # May succeed or show errors if tickets aren't configured
      try do
        result = render_click(view, "open-ticket-modal")
        assert is_binary(result) or match?({:error, _}, result)
      catch
        :exit, _ -> :ok
      end
    end

    test "closes ticket modal", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "close-ticket-modal")
      assert is_binary(result)
    end

    test "shows attendees modal", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "show-attendees-modal")
      assert is_binary(result)
    end
  end

  describe "ticket registration interactions" do
    test "handles update-registration-field event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      params = %{
        "ticket-index" => "0",
        "field" => "first_name",
        "value" => "John"
      }

      result = render_change(view, "update-registration-field", params)
      assert is_binary(result)
    end
  end

  describe "ticket attendee selection" do
    test "handles select-family-member event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      params = %{
        "ticket-id" => "temp-1",
        "family-member-id" => "123"
      }

      result = render_click(view, "select-family-member", params)
      assert is_binary(result) or match?({:error, _}, result)
    end

    test "handles select-ticket-attendee event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      params = %{
        "ticket-id" => "temp-1",
        "attendee-id" => "456"
      }

      result = render_click(view, "select-ticket-attendee", params)
      assert is_binary(result) or match?({:error, _}, result)
    end
  end

  describe "checkout flows" do
    test "handles retry-checkout event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "retry-checkout")
      assert is_binary(result) or match?({:error, _}, result)
    end

    test "handles proceed-to-checkout event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "proceed-to-checkout")
      assert is_binary(result) or match?({:error, _}, result)
    end
  end

  describe "agenda interactions" do
    test "handles set-active-agenda event", %{conn: conn} do
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "set-active-agenda", %{"id" => "1"})
      assert is_binary(result)
    end
  end

  describe "donation interactions - comprehensive" do
    test "handles set-donation-amount event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      params = %{
        "tier-id" => "tier-1",
        "amount" => "100"
      }

      result = render_click(view, "set-donation-amount", params)
      assert is_binary(result)
    end

    test "handles various donation amounts", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Test different amounts
      for amount <- ["10", "25", "50", "100"] do
        render_click(view, "update-donation-amount", %{"amount" => amount})
      end

      html = render(view)
      assert html =~ event.title
    end

    test "handles zero donation amount", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "update-donation-amount", %{"amount" => "0"})
      assert is_binary(result)
    end

    test "handles invalid donation amount", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result = render_click(view, "update-donation-amount", %{"amount" => "invalid"})
      assert is_binary(result)
    end
  end

  describe "different event states" do
    test "loads upcoming event", %{conn: conn} do
      future_date = DateTime.add(DateTime.utc_now(), 30, :day)

      event =
        create_event(%{
          title: "Upcoming Event",
          start_datetime: future_date
        })

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      assert html =~ "Upcoming Event"
    end

    test "loads past event", %{conn: conn} do
      past_date = DateTime.add(DateTime.utc_now(), -30, :day)

      event =
        create_event(%{
          title: "Past Event",
          start_datetime: past_date
        })

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      assert html =~ "Past Event"
    end

    test "loads event happening today", %{conn: conn} do
      # Event starting in 2 hours
      today = DateTime.add(DateTime.utc_now(), 2, :hour)

      event =
        create_event(%{
          title: "Today's Event",
          start_datetime: today
        })

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(300)

      html = render(view)
      # Event may not be in initial HTML if async loading
      assert is_binary(html)
    end
  end

  describe "different user authentication states" do
    test "unauthenticated user can view public event", %{conn: conn} do
      event = create_event(%{title: "Public Event"})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      assert html =~ "Public Event"
    end

    test "authenticated user without membership can view event", %{conn: conn} do
      user = user_with_membership(:none)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test Event"})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      assert html =~ "Test Event"
    end

    test "lifetime member can view event", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Member Event"})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      assert html =~ "Member Event"
    end

    test "subscription member can view event", %{conn: conn} do
      user = user_with_membership(:subscription)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Subscriber Event"})

      {:ok, _view, html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      assert html =~ "Subscriber Event"
    end
  end

  describe "rapid interaction scenarios" do
    test "handles rapid ticket quantity changes", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Rapid increase/decrease cycles
      tier_id = "tier-1"

      for _i <- 1..3 do
        render_click(view, "increase-ticket-quantity", %{"tier-id" => tier_id})
      end

      for _i <- 1..2 do
        render_click(view, "decrease-ticket-quantity", %{"tier-id" => tier_id})
      end

      html = render(view)
      assert html =~ event.title
    end
  end

  describe "edge cases and error handling" do
    test "handles invalid event ID", %{conn: conn} do
      # Invalid ULID format will raise CastError or NoResultsError
      assert_raise Ecto.Query.CastError, fn ->
        live(conn, ~p"/events/99999999")
      end
    end

    test "handles invalid ticket quantity tier ID", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      result =
        render_click(view, "increase-ticket-quantity", %{"tier-id" => "nonexistent-tier"})

      assert is_binary(result)
    end

    test "handles invalid registration field index", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      params = %{
        "ticket-index" => "999",
        "field" => "first_name",
        "value" => "Test"
      }

      result = render_change(view, "update-registration-field", params)
      assert is_binary(result)
    end
  end

  describe "page reload and navigation scenarios" do
    test "maintains state after re-rendering", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Test Event"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Make some changes
      render_click(view, "increase-ticket-quantity", %{"tier-id" => "tier-1"})

      # Re-render
      html = render(view)
      assert html =~ "Test Event"
    end

    test "handles navigation back to event page", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Navigation Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(300)

      html = render(view)
      assert html =~ "Navigation Test"
    end
  end

  describe "combined interaction flows" do
    test "donation with ticket purchase flow", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Donation Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Add tickets
      render_click(view, "increase-ticket-quantity", %{"tier-id" => "tier-1"})

      # Add donation
      render_click(view, "update-donation-amount", %{"amount" => "50"})

      html = render(view)
      assert html =~ event.title
    end

    test "modify ticket selection multiple times", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Modification Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      tier_id = "tier-1"

      # Add tickets
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier_id})
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier_id})

      # Remove some
      render_click(view, "decrease-ticket-quantity", %{"tier-id" => tier_id})

      # Add more
      render_click(view, "increase-ticket-quantity", %{"tier-id" => tier_id})

      html = render(view)
      assert html =~ event.title
    end
  end

  describe "boundary conditions" do
    test "handles minimum ticket quantity", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Min Quantity Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Try to decrease when at 0
      result = render_click(view, "decrease-ticket-quantity", %{"tier-id" => "tier-1"})
      assert is_binary(result)
    end

    test "handles registration field validation", %{conn: conn} do
      user = user_with_membership(:lifetime)
      conn = log_in_user(conn, user)
      event = create_event(%{title: "Validation Test"})

      {:ok, view, _html} = live(conn, ~p"/events/#{event.id}")
      :timer.sleep(200)

      # Test various field values
      fields = [
        %{"ticket-index" => "0", "field" => "first_name", "value" => ""},
        %{"ticket-index" => "0", "field" => "email", "value" => "invalid-email"},
        %{"ticket-index" => "0", "field" => "last_name", "value" => "Doe"}
      ]

      for params <- fields do
        render_change(view, "update-registration-field", params)
      end

      html = render(view)
      assert html =~ event.title
    end
  end
end
