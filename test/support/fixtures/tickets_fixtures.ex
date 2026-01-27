defmodule Ysc.TicketsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Ysc.Tickets` context.
  """

  alias Ysc.Tickets
  alias Ysc.EventsFixtures

  def ticket_order_fixture(attrs \\ %{}) do
    user = attrs[:user] || Ysc.AccountsFixtures.user_fixture()
    event = attrs[:event] || EventsFixtures.event_fixture()
    tier = attrs[:tier] || EventsFixtures.ticket_tier_fixture(%{event_id: event.id})

    ticket_selections = attrs[:ticket_selections] || %{tier.id => 1}

    {:ok, ticket_order} =
      Tickets.create_ticket_order(user.id, event.id, ticket_selections)

    ticket_order
  end
end
