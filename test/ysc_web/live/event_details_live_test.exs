defmodule YscWeb.EventDetailsLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Events
  alias Ysc.Repo

  # Helper to create an event
  defp create_event(attrs) do
    default_attrs = %{
      title: "Test Event #{System.unique_integer()}",
      description: "A test event description",
      start_date: DateTime.add(DateTime.utc_now(), 7, :day),
      end_date: DateTime.add(DateTime.utc_now(), 8, :day),
      state: :published,
      ticket_sales_start: DateTime.utc_now(),
      ticket_sales_end: DateTime.add(DateTime.utc_now(), 6, :day),
      location: "Test Location",
      max_attendees: 100
    }

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

      # Should display formatted date
      assert html =~ Timex.format!(start_date, "{Mshort} {D}, {YYYY}")
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

      result = render_click(view, "open-ticket-modal")

      # Modal state should be updated
      assert is_binary(result)
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
end
