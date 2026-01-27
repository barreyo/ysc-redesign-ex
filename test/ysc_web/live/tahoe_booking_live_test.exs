defmodule YscWeb.TahoeBookingLiveTest do
  @moduledoc """
  Tests for TahoeBookingLive.
  """
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "renders tahoe booking page", %{conn: conn, user: user} do
    # Give user lifetime membership
    user
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at: DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Ysc.Repo.update!()

    {:ok, _index_live, html} = live(conn, ~p"/bookings/tahoe")

    assert html =~ "Tahoe"
  end

  test "handles date parameters", %{conn: conn, user: user} do
    user
    |> Ecto.Changeset.change(
      lifetime_membership_awarded_at: DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Ysc.Repo.update!()

    checkin = Date.utc_today() |> Date.add(30)
    checkout = Date.add(checkin, 3)

    params = %{
      "checkin_date" => Date.to_string(checkin),
      "checkout_date" => Date.to_string(checkout)
    }

    {:ok, _index_live, html} = live(conn, ~p"/bookings/tahoe?#{URI.encode_query(params)}")

    assert html =~ "Tahoe"
  end
end
