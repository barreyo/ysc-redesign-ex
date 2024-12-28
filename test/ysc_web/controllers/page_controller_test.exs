defmodule YscWeb.PageControllerTest do
  use YscWeb.ConnCase

  import Ysc.AccountsFixtures

  describe "GET /" do
    test "renders home page", %{conn: conn} do
      conn = get(conn, ~p"/")
      # Adjust the content based on your actual home page
      assert html_response(conn, 200) =~ "Home"
    end
  end

  describe "GET /pending-review" do
    setup %{conn: conn} do
      user = user_fixture()
      conn = assign(conn, :current_user, user)
      %{conn: conn, user: user}
    end

    test "renders pending review page with submission from Pacific timezone", %{conn: conn} do
      # Setup submission date in Pacific timezone
      submitted_date = DateTime.utc_now()
      timezone = "America/Los_Angeles"

      # Mock the get_signup_application_submission_date function
      expect(Ysc.Accounts, :get_signup_application_submission_date, fn user_id ->
        %{submit_date: submitted_date, timezone: timezone}
      end)

      conn = get(conn, ~p"/pending-review")

      # Adjust based on your actual page content
      assert html_response(conn, 200) =~ "Application Review"
      assert conn.assigns.application_submitted_date != nil
      # Since Timex.from_now returns a string with "ago"
      assert conn.assigns.time_delta =~ "ago"
    end

    test "renders pending review page with submission from different timezone", %{conn: conn} do
      # Setup submission date in a different timezone
      submitted_date = DateTime.utc_now()
      timezone = "Europe/Stockholm"

      # Mock the get_signup_application_submission_date function
      expect(Ysc.Accounts, :get_signup_application_submission_date, fn user_id ->
        %{submit_date: submitted_date, timezone: timezone}
      end)

      conn = get(conn, ~p"/pending-review")

      assert html_response(conn, 200)
      assert conn.assigns.application_submitted_date != nil
      assert conn.assigns.time_delta =~ "ago"
    end

    test "handles missing timezone by defaulting to America/Los_Angeles", %{conn: conn} do
      # Setup submission date without timezone
      submitted_date = DateTime.utc_now()

      # Mock the get_signup_application_submission_date function
      expect(Ysc.Accounts, :get_signup_application_submission_date, fn user_id ->
        %{submit_date: submitted_date, timezone: nil}
      end)

      conn = get(conn, ~p"/pending-review")

      assert html_response(conn, 200)
      assert conn.assigns.application_submitted_date != nil
      assert conn.assigns.time_delta =~ "ago"
    end

    test "requires authentication" do
      conn = build_conn()
      conn = get(conn, ~p"/pending-review")
      # Adjust based on your authentication redirect path
      assert redirected_to(conn) == ~p"/login"
    end
  end
end
