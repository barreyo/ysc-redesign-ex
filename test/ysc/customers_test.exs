defmodule Ysc.CustomersTest do
  @moduledoc """
  Tests for Ysc.Customers context module.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Customers
  alias Ysc.Accounts.User
  import Ysc.AccountsFixtures

  setup do
    Ysc.Ledgers.ensure_basic_accounts()
    :ok
  end

  describe "customer_from_stripe_id/1" do
    test "returns user with matching stripe_id" do
      user = user_fixture()
      user = update_user_stripe_id(user, "cus_test_123")

      found = Customers.customer_from_stripe_id("cus_test_123")
      assert found.id == user.id
    end

    test "returns nil for non-existent stripe_id" do
      assert Customers.customer_from_stripe_id("cus_nonexistent") == nil
    end
  end

  describe "subscriptions/1" do
    test "returns subscriptions for a user" do
      user = user_fixture()

      # Create a subscription for the user
      {:ok, subscription} =
        Ysc.Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_test_123",
          stripe_status: "active",
          name: "Test Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      subscriptions = Customers.subscriptions(user)
      assert length(subscriptions) >= 1
      assert Enum.any?(subscriptions, &(&1.id == subscription.id))
    end

    test "returns empty list for user with no subscriptions" do
      user = user_fixture()
      subscriptions = Customers.subscriptions(user)
      assert subscriptions == []
    end
  end

  describe "subscribed_to_price?/2" do
    test "returns true when user is subscribed to price" do
      user = user_fixture()

      {:ok, subscription} =
        Ysc.Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_test_123",
          stripe_status: "active",
          name: "Test Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      # Create subscription item with price
      {:ok, _item} =
        Ysc.Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_price_id: "price_test_123",
          stripe_product_id: "prod_test_123",
          stripe_id: "si_test_123",
          quantity: 1
        })

      assert Customers.subscribed_to_price?(user, "price_test_123") == true
    end

    test "returns false when user is not subscribed to price" do
      user = user_fixture()
      assert Customers.subscribed_to_price?(user, "price_nonexistent") == false
    end
  end

  # Helper function
  defp update_user_stripe_id(user, stripe_id) do
    user
    |> User.update_user_changeset(%{stripe_id: stripe_id})
    |> Ysc.Repo.update!()
  end
end
