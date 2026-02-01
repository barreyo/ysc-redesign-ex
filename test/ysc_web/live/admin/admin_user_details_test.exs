defmodule YscWeb.AdminUserDetailsLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  setup :register_and_log_in_admin

  describe "mount" do
    test "loads user details for viewing", %{conn: conn} do
      user = user_fixture(%{first_name: "John", last_name: "Doe"})

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "John"
      assert html =~ "Doe"
    end

    test "displays user avatar", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert has_element?(view, "[class*='w-24 h-24 rounded-full']")
    end

    test "displays back button", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Back"
    end

    test "capitalizes user name", %{conn: conn} do
      user = user_fixture(%{first_name: "jane", last_name: "smith"})

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Jane"
      assert html =~ "Smith"
    end
  end

  describe "navigation tabs" do
    test "displays profile tab", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Profile"
    end

    test "displays tickets tab", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Tickets"
    end

    test "displays bookings tab", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Bookings"
    end

    test "displays application tab", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Application"
    end

    test "profile tab is active by default", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert has_element?(view, "a.active", "Profile")
    end

    test "can navigate to orders tab", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      {:ok, _view, orders_html} =
        view
        |> element("a[href$='/details/orders']")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/users/#{user.id}/details/orders")

      assert orders_html =~ "Tickets"
    end

    test "can navigate to bookings tab", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      {:ok, _view, bookings_html} =
        view
        |> element("a[href$='/details/bookings']")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/users/#{user.id}/details/bookings")

      assert bookings_html =~ "Bookings"
    end

    test "can navigate to application tab", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      {:ok, _view, application_html} =
        view
        |> element("a[href$='/details/application']")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/users/#{user.id}/details/application")

      assert application_html =~ "Application"
    end
  end

  describe "tab highlighting" do
    test "highlights active tab with correct styles", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      # Active tab should have blue styling
      assert html =~ "text-blue-600 border-blue-600"
    end

    test "non-active tabs have hover styles", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      # Non-active tabs should have hover styling
      assert html =~ "hover:text-zinc-600 hover:border-zinc-300"
    end
  end

  describe "back navigation" do
    test "back button links to users list", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert view
             |> element("a", "Back")
             |> render()
             |> then(&(&1 =~ "/admin/users"))
    end
  end

  describe "user avatar" do
    test "displays user avatar with email", %{conn: conn} do
      user = user_fixture(%{email: "test@example.com"})

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      # Avatar component should be rendered
      assert has_element?(view, "[class*='rounded-full']")
    end

    test "displays avatar with correct size", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "w-24 h-24"
    end
  end

  describe "page title" do
    test "displays user name as page title", %{conn: conn} do
      user = user_fixture(%{first_name: "Alice", last_name: "Johnson"})

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Alice Johnson"
      assert html =~ "text-2xl font-semibold"
    end
  end

  describe "layout" do
    test "uses admin app layout", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      # Should have admin layout elements
      assert html =~ "YSC.org Admin"
    end

    test "displays current user info in navigation", %{conn: conn, user: admin_user} do
      viewed_user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{viewed_user.id}/details")

      # Admin user info should be displayed
      assert html =~ admin_user.email
    end
  end

  defp register_and_log_in_admin(%{conn: conn}) do
    user = user_fixture(%{role: :admin})
    %{conn: log_in_user(conn, user), user: user}
  end
end
