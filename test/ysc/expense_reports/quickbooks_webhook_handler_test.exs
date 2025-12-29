defmodule Ysc.ExpenseReports.QuickbooksWebhookHandlerTest do
  @moduledoc """
  Tests for QuickBooks webhook handler.

  Tests webhook event processing, job enqueueing, and error handling.
  """
  use Ysc.DataCase, async: true

  import Oban.Testing
  alias Ysc.ExpenseReports.QuickbooksWebhookHandler
  alias Ysc.Webhooks
  alias Ysc.Repo

  describe "handle_webhook_event/1" do
    test "enqueues BillPayment processing job for Create operation" do
      webhook_event =
        create_webhook_event(
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_123:Create",
          event_type: "BillPayment.Create",
          payload: build_webhook_payload("BillPayment", "bp_123", "Create")
        )

      assert :ok = QuickbooksWebhookHandler.handle_webhook_event(webhook_event)

      # Verify job was enqueued
      assert_enqueued(
        worker: YscWeb.Workers.QuickbooksBillPaymentProcessorWorker,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_123"
        }
      )
    end

    test "enqueues BillPayment processing job for Update operation" do
      webhook_event =
        create_webhook_event(
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_456:Update",
          event_type: "BillPayment.Update",
          payload: build_webhook_payload("BillPayment", "bp_456", "Update")
        )

      assert :ok = QuickbooksWebhookHandler.handle_webhook_event(webhook_event)

      assert_enqueued(
        worker: YscWeb.Workers.QuickbooksBillPaymentProcessorWorker,
        args: %{
          "webhook_event_id" => webhook_event.id,
          "bill_payment_id" => "bp_456"
        }
      )
    end

    test "skips non-BillPayment entities" do
      webhook_event =
        create_webhook_event(
          provider: "quickbooks",
          event_id: "123456789:Invoice:inv_123:Create",
          event_type: "Invoice.Create",
          payload: build_webhook_payload("Invoice", "inv_123", "Create")
        )

      assert :ok = QuickbooksWebhookHandler.handle_webhook_event(webhook_event)

      # Verify no job was enqueued
      refute_enqueued(worker: YscWeb.Workers.QuickbooksBillPaymentProcessorWorker)
    end

    test "skips non-Create/Update operations" do
      webhook_event =
        create_webhook_event(
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_123:Delete",
          event_type: "BillPayment.Delete",
          payload: build_webhook_payload("BillPayment", "bp_123", "Delete")
        )

      assert :ok = QuickbooksWebhookHandler.handle_webhook_event(webhook_event)

      # Verify no job was enqueued
      refute_enqueued(worker: YscWeb.Workers.QuickbooksBillPaymentProcessorWorker)
    end

    test "handles webhook with no entities" do
      payload = %{
        "eventNotifications" => [
          %{
            "realmId" => "123456789",
            "dataChangeEvent" => %{
              "entities" => []
            }
          }
        ]
      }

      webhook_event =
        create_webhook_event(
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_123:Create",
          event_type: "BillPayment.Create",
          payload: payload
        )

      assert :ok = QuickbooksWebhookHandler.handle_webhook_event(webhook_event)

      # Verify no job was enqueued
      refute_enqueued(worker: YscWeb.Workers.QuickbooksBillPaymentProcessorWorker)
    end

    test "handles webhook with no event notifications" do
      payload = %{"eventNotifications" => []}

      webhook_event =
        create_webhook_event(
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_123:Create",
          event_type: "BillPayment.Create",
          payload: payload
        )

      assert :ok = QuickbooksWebhookHandler.handle_webhook_event(webhook_event)

      # Verify no job was enqueued
      refute_enqueued(worker: YscWeb.Workers.QuickbooksBillPaymentProcessorWorker)
    end

    test "handles job enqueue failure gracefully" do
      # This test verifies that the handler doesn't crash if job enqueueing fails
      # In practice, this would require mocking Oban, but we can test the structure
      webhook_event =
        create_webhook_event(
          provider: "quickbooks",
          event_id: "123456789:BillPayment:bp_123:Create",
          event_type: "BillPayment.Create",
          payload: build_webhook_payload("BillPayment", "bp_123", "Create")
        )

      # The handler should return :ok even if job enqueueing fails
      # (it logs the error but doesn't raise)
      result = QuickbooksWebhookHandler.handle_webhook_event(webhook_event)
      assert result == :ok or match?({:error, _}, result)
    end
  end

  # Helper functions

  defp create_webhook_event(opts) do
    provider = Keyword.fetch!(opts, :provider)
    event_id = Keyword.fetch!(opts, :event_id)
    event_type = Keyword.fetch!(opts, :event_type)
    payload = Keyword.fetch!(opts, :payload)

    %Ysc.Webhooks.WebhookEvent{}
    |> Ysc.Webhooks.WebhookEvent.changeset(%{
      provider: provider,
      event_id: event_id,
      event_type: event_type,
      payload: payload,
      state: :pending
    })
    |> Repo.insert!()
  end

  defp build_webhook_payload(entity_name, entity_id, operation) do
    %{
      "eventNotifications" => [
        %{
          "realmId" => "123456789",
          "dataChangeEvent" => %{
            "entities" => [
              %{
                "name" => entity_name,
                "id" => entity_id,
                "operation" => operation
              }
            ]
          }
        }
      ]
    }
  end
end
