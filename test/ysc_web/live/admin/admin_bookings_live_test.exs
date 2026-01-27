defmodule YscWeb.Admin.AdminBookingsLiveTest do
  @moduledoc """
  Tests for AdminBookingsLive.
  """
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  setup :register_and_log_in_user

  test "requires admin access", %{conn: conn, user: user} do
    # Make user admin
    user
    |> Ecto.Changeset.change(role: "admin")
    |> Ysc.Repo.update!()

    {:ok, _index_live, html} = live(conn, ~p"/admin/bookings")

    assert html =~ "Bookings"
  end
end
