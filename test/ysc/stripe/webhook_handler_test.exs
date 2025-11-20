defmodule Ysc.Stripe.WebhookHandlerTest do
  use Ysc.DataCase
  alias Ysc.Stripe.WebhookHandler
  alias Ysc.Subscriptions
  alias Ysc.Ledgers
  import Ysc.AccountsFixtures

  # Mock Stripe.Event struct since we don't want to depend on the library struct definition if possible,
  # but since the code matches on %Stripe.Event{}, we need it.
  # We'll assume the alias is available or we define a minimal one if needed.
  # Checking the code, it uses `Stripe.Event`.

  describe "handle_event/1 with invoice.payment_succeeded" do
    setup do
      user = user_fixture()
      # Add Stripe ID to user
      {:ok, user} =
        user
        |> Ecto.Changeset.change(stripe_id: "cus_test_123")
        |> Ysc.Repo.update()

      # Create a subscription for the user
      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          name: "Membership",
          stripe_id: "sub_test_123",
          stripe_status: "active",
          start_date: DateTime.utc_now(),
          current_period_start: DateTime.utc_now(),
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      %{user: user, subscription: subscription}
    end

    test "resolves subscription from customer when subscription id is null in invoice", %{
      user: user,
      subscription: subscription
    } do
      # Construct the invoice payload with null subscription but valid customer and billing reason
      invoice_data = %{
        "id" => "in_test_123",
        "object" => "invoice",
        "customer" => user.stripe_id,
        "subscription" => nil,
        "billing_reason" => "subscription_create",
        "amount_paid" => 4500,
        "description" => "Test Invoice",
        "number" => "INV-001",
        # Null charge to avoid Stripe API calls
        "charge" => nil,
        "metadata" => %{}
      }

      # Construct the event
      event = %Stripe.Event{
        id: "evt_test_123",
        type: "invoice.payment_succeeded",
        data: %{object: invoice_data},
        api_version: "2025-10-29.clover",
        created: System.os_time(:second),
        livemode: false,
        pending_webhooks: 1,
        request: %{id: "req_123", idempotency_key: "key_123"},
        object: "event",
        account: "acct_test"
      }

      # Make sure basic accounts exist for ledger processing
      Ledgers.ensure_basic_accounts()

      # Run the handler
      # Note: We might get errors if Ysc.Webhooks tries to write to DB and fails constraints or something,
      # but we are in DataCase sandbox.
      # We also assume the handler captures exceptions and logs them, but returns :ok.
      # Since we want to verify success, we check side effects.

      assert :ok = WebhookHandler.handle_event(event)

      # Check if payment was created in Ledger
      payment = Ledgers.get_payment_by_external_id("in_test_123")
      assert payment != nil
      assert payment.user_id == user.id
      # Assert amount using string representation to avoid confusion with Money.new args
      assert Money.to_string!(payment.amount) == "$45.00"

      # Verify it's linked to the subscription via ledger entries
      subscription_payments = Ledgers.get_payments_for_subscription(subscription.id)
      assert Enum.any?(subscription_payments, fn p -> p.id == payment.id end)
    end

    test "skips processing when subscription is null and cannot be resolved", %{user: user} do
      # Invoice with null subscription and NO billing_reason match
      invoice_data = %{
        "id" => "in_test_skip",
        "object" => "invoice",
        "customer" => user.stripe_id,
        "subscription" => nil,
        # Not subscription_create
        "billing_reason" => "manual",
        "amount_paid" => 4500,
        "description" => "Manual Invoice",
        "charge" => nil
      }

      event = %Stripe.Event{
        id: "evt_test_skip",
        type: "invoice.payment_succeeded",
        data: %{object: invoice_data},
        object: "event"
      }

      Ledgers.ensure_basic_accounts()

      assert :ok = WebhookHandler.handle_event(event)

      # Should NOT create payment
      assert Ledgers.get_payment_by_external_id("in_test_skip") == nil
    end
  end
end
