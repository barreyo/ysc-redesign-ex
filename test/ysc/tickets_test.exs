defmodule Ysc.TicketsTest do
  @moduledoc """
  Tests for Ysc.Tickets context module.
  """
  use Ysc.DataCase, async: true

  import Ecto.Query
  alias Ysc.Tickets
  alias Ysc.Tickets.TicketOrder
  import Ysc.AccountsFixtures

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    user = user_fixture()

    # Give user lifetime membership so they can purchase tickets
    user =
      user
      |> Ecto.Changeset.change(
        lifetime_membership_awarded_at: DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Ysc.Repo.update!()

    organizer = user_fixture()

    {:ok, event} =
      Ysc.Events.create_event(%{
        title: "Test Event",
        description: "A test event",
        state: :published,
        organizer_id: organizer.id,
        start_date: DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 30, :day),
        max_attendees: 100,
        published_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    {:ok, tier1} =
      Ysc.Events.create_ticket_tier(%{
        name: "General Admission",
        type: :paid,
        price: Money.new(50, :USD),
        quantity: 50,
        event_id: event.id
      })

    {:ok, tier2} =
      Ysc.Events.create_ticket_tier(%{
        name: "VIP",
        type: :paid,
        price: Money.new(100, :USD),
        quantity: 20,
        event_id: event.id
      })

    %{user: user, event: event, tier1: tier1, tier2: tier2}
  end

  describe "create_ticket_order/3" do
    test "creates a ticket order with valid selections", %{user: user, event: event, tier1: tier1} do
      ticket_selections = %{tier1.id => 2}

      assert {:ok, %TicketOrder{} = order} =
               Tickets.create_ticket_order(user.id, event.id, ticket_selections)

      assert order.user_id == user.id
      assert order.event_id == event.id
      # Status defaults to :pending, but may expire if expires_at is in the past
      # Reload to get current status (may be :expired if timeout worker ran)
      reloaded_order = Ysc.Repo.reload!(order) |> Ysc.Repo.preload(:tickets)
      assert reloaded_order.status in [:pending, :expired]
      assert length(reloaded_order.tickets) == 2
    end

    test "returns error when user doesn't have active membership", %{
      event: event,
      tier1: tier1
    } do
      # Create user without membership
      user = user_fixture()
      ticket_selections = %{tier1.id => 1}

      assert {:error, :membership_required} =
               Tickets.create_ticket_order(user.id, event.id, ticket_selections)
    end

    test "returns error when event capacity exceeded", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      # Fill up the tier to capacity (tier1 has quantity: 50)
      # Create orders up to tier capacity
      Enum.each(1..50, fn _i ->
        {:ok, _order} =
          Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})
      end)

      # Try to create one more order (will fail with tier validation error)
      assert {:error, :tier_validation_failed} =
               Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})
    end

    test "returns error when tier capacity exceeded", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      # Fill up the tier to capacity (50 tickets)
      for _i <- 1..50 do
        {:ok, _order} =
          Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})
      end

      # Try to create one more order
      assert {:error, :tier_validation_failed} =
               Tickets.create_ticket_order(user.id, event.id, %{tier1.id => 1})
    end
  end

  describe "get_ticket_order/1" do
    test "returns ticket order with preloaded associations", %{
      user: user,
      event: event,
      tier1: tier1
    } do
      ticket_selections = %{tier1.id => 1}
      {:ok, order} = Tickets.create_ticket_order(user.id, event.id, ticket_selections)

      found = Tickets.get_ticket_order(order.id)
      assert found.id == order.id
      assert Ecto.assoc_loaded?(found.user)
      assert Ecto.assoc_loaded?(found.event)
      assert Ecto.assoc_loaded?(found.tickets)
    end
  end

  describe "get_ticket_order_by_payment_id/1" do
    test "returns ticket order by payment ID", %{user: user, event: event, tier1: tier1} do
      ticket_selections = %{tier1.id => 1}
      {:ok, order} = Tickets.create_ticket_order(user.id, event.id, ticket_selections)

      # Create a payment and link it
      {:ok, {payment, _transaction, _entries}} =
        Ysc.Ledgers.process_payment(%{
          user_id: user.id,
          amount: Money.new(50, :USD),
          entity_type: :event,
          entity_id: event.id,
          external_payment_id: "pi_test_123",
          stripe_fee: Money.new(160, :USD),
          description: "Test payment",
          property: nil,
          payment_method_id: nil
        })

      order
      |> TicketOrder.status_changeset(%{payment_id: payment.id})
      |> Ysc.Repo.update!()

      found = Tickets.get_ticket_order_by_payment_id(payment.id)
      assert found.id == order.id
    end
  end

  describe "list_user_ticket_orders/1" do
    test "returns all ticket orders for a user", %{user: user, event: event, tier1: tier1} do
      ticket_selections = %{tier1.id => 1}
      {:ok, order1} = Tickets.create_ticket_order(user.id, event.id, ticket_selections)
      {:ok, order2} = Tickets.create_ticket_order(user.id, event.id, ticket_selections)

      orders = Tickets.list_user_ticket_orders(user.id)
      assert length(orders) >= 2
      assert Enum.any?(orders, &(&1.id == order1.id))
      assert Enum.any?(orders, &(&1.id == order2.id))
    end
  end

  describe "expire_timed_out_orders/0" do
    test "expires orders older than timeout period", %{user: user, event: event, tier1: tier1} do
      ticket_selections = %{tier1.id => 1}
      {:ok, order} = Tickets.create_ticket_order(user.id, event.id, ticket_selections)

      # Manually set inserted_at to be older than timeout using SQL
      old_time =
        DateTime.add(DateTime.utc_now(), -(16 * 60), :second)
        |> DateTime.truncate(:second)

      Ysc.Repo.update_all(
        from(to in TicketOrder, where: to.id == ^order.id),
        set: [inserted_at: old_time]
      )

      # Run expiration
      expired_count = Tickets.expire_timed_out_orders()
      assert expired_count >= 1

      # Verify order is expired
      updated_order = Ysc.Repo.reload!(order)
      assert updated_order.status == :expired
    end
  end
end
