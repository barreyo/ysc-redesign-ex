defmodule Ysc.SubscriptionsTest do
  @moduledoc """
  Tests for Ysc.Subscriptions context.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.Subscription
  import Ysc.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "subscriptions" do
    test "create_subscription/1 creates a subscription", %{user: user} do
      attrs = %{
        user_id: user.id,
        stripe_id: "sub_123",
        stripe_status: "active",
        name: "Membership",
        current_period_end: DateTime.utc_now() |> DateTime.add(30, :day)
      }

      assert {:ok, %Subscription{} = sub} = Subscriptions.create_subscription(attrs)
      assert sub.stripe_id == "sub_123"
      assert sub.stripe_status == "active"
    end

    test "active?/1 returns true for active/trialing with valid dates", %{user: user} do
      now = DateTime.utc_now()
      future_date = DateTime.add(now, 30, :day)
      past_date = DateTime.add(now, -1, :day)

      # Active subscription with future period end
      active_sub = %Subscription{
        stripe_status: "active",
        current_period_end: future_date,
        ends_at: nil
      }

      # Trialing subscription with future period end
      trialing_sub = %Subscription{
        stripe_status: "trialing",
        current_period_end: future_date,
        ends_at: nil
      }

      # Cancelled subscription
      cancelled_sub = %Subscription{stripe_status: "cancelled"}

      # Active subscription with expired period end
      expired_active = %Subscription{
        stripe_status: "active",
        current_period_end: past_date,
        ends_at: nil
      }

      # Active subscription with ends_at in the past
      ended_subscription = %Subscription{
        stripe_status: "active",
        current_period_end: future_date,
        ends_at: past_date
      }

      # Active subscription with nil current_period_end (defensive check)
      no_period_end = %Subscription{
        stripe_status: "active",
        current_period_end: nil,
        ends_at: nil
      }

      assert Subscriptions.active?(active_sub)
      assert Subscriptions.active?(trialing_sub)
      refute Subscriptions.active?(cancelled_sub)
      refute Subscriptions.active?(expired_active)
      refute Subscriptions.active?(ended_subscription)
      refute Subscriptions.active?(no_period_end)
    end

    test "cancelled?/1 checks status, ends_at, and current_period_end", %{user: user} do
      now = DateTime.utc_now()
      past_date = DateTime.add(now, -1, :day)
      future_date = DateTime.add(now, 1, :day)

      # Cancelled by status
      cancelled_status = %Subscription{stripe_status: "cancelled"}
      assert Subscriptions.cancelled?(cancelled_status)

      # Cancelled because ends_at is in the past
      ended_subscription = %Subscription{
        stripe_status: "active",
        ends_at: past_date,
        current_period_end: future_date
      }

      assert Subscriptions.cancelled?(ended_subscription)

      # Cancelled because current_period_end is in the past
      expired_subscription = %Subscription{
        stripe_status: "active",
        current_period_end: past_date,
        ends_at: nil
      }

      assert Subscriptions.cancelled?(expired_subscription)

      # Not cancelled - ends_at is in the future (scheduled cancellation)
      scheduled_cancellation = %Subscription{
        stripe_status: "active",
        ends_at: future_date,
        current_period_end: future_date
      }

      refute Subscriptions.cancelled?(scheduled_cancellation)

      # Not cancelled - active subscription
      active = %Subscription{
        stripe_status: "active",
        ends_at: nil,
        current_period_end: future_date
      }

      refute Subscriptions.cancelled?(active)

      # Nil subscription
      refute Subscriptions.cancelled?(nil)
    end

    test "valid?/1 checks expiration dates", %{user: user} do
      now = DateTime.utc_now()
      future_date = DateTime.add(now, 30, :day)
      past_date = DateTime.add(now, -1, :day)

      # Valid subscription
      valid_sub = %Subscription{
        stripe_status: "active",
        current_period_end: future_date,
        ends_at: nil
      }

      assert Subscriptions.valid?(valid_sub)

      # Invalid - expired period end
      expired_sub = %Subscription{
        stripe_status: "active",
        current_period_end: past_date,
        ends_at: nil
      }

      refute Subscriptions.valid?(expired_sub)

      # Invalid - ends_at in past
      ended_sub = %Subscription{
        stripe_status: "active",
        current_period_end: future_date,
        ends_at: past_date
      }

      refute Subscriptions.valid?(ended_sub)
    end
  end
end
