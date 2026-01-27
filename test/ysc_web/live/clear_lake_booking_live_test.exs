defmodule YscWeb.ClearLakeBookingLiveTest do
  @moduledoc """
  Tests for ClearLakeBookingLive.
  """
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  setup :register_and_log_in_user

  test "renders clear lake booking page", %{conn: conn, user: user} do
    # Give user lifetime membership
    user
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at: DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Ysc.Repo.update!()

    {:ok, _index_live, html} = live(conn, ~p"/bookings/clear-lake")

    assert html =~ "Clear Lake"
  end

  test "handles date parameters", %{conn: conn, user: user} do
    user
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at: DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Ysc.Repo.update!()

    checkin = Date.utc_today() |> Date.add(30)
    checkout = Date.add(checkin, 2)

    params = %{
      "checkin_date" => Date.to_string(checkin),
      "checkout_date" => Date.to_string(checkout)
    }

    {:ok, _index_live, html} = live(conn, ~p"/bookings/clear-lake?#{URI.encode_query(params)}")

    assert html =~ "Clear Lake"
  end
end
