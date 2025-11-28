#!/usr/bin/env elixir

# Script to reprocess a Stripe payout that was created with the old method
# This will re-link all payments, refunds, and update fee_total using the BalanceTransaction API

# Usage:
#   mix run reprocess_payout.exs <stripe_payout_id>
#   mix run reprocess_payout.exs po_1SYFlzREiftrEncLDHTuRysd
#
# Or in IEx:
#   iex> Code.load_file("reprocess_payout.exs")
#   iex> ReprocessPayout.reprocess("po_1SYFlzREiftrEncLDHTuRysd")

alias Ysc.Ledgers
alias Ysc.Stripe.WebhookHandler
alias Ysc.Repo
import Ecto.Query

defmodule ReprocessPayout do
  def reprocess(stripe_payout_id) when is_binary(stripe_payout_id) do
    require Logger

    Logger.info("Starting payout reprocessing", stripe_payout_id: stripe_payout_id)

    # Get the payout from the database
    case Ledgers.get_payout_by_stripe_id(stripe_payout_id) do
      nil ->
        IO.puts("❌ Payout not found in database: #{stripe_payout_id}")
        {:error, :not_found}

      payout ->
        IO.puts("📋 Found payout in database:")
        IO.puts("   ID: #{payout.id}")
        IO.puts("   Stripe ID: #{payout.stripe_payout_id}")
        IO.puts("   Amount: #{Money.to_string!(payout.amount)}")

        IO.puts(
          "   Fee Total: #{if payout.fee_total, do: Money.to_string!(payout.fee_total), else: "not set"}"
        )

        IO.puts("   Status: #{payout.status}")

        # Get current linked transactions
        payout = Repo.preload(payout, [:payments, :refunds])
        IO.puts("\n📊 Current linked transactions:")
        IO.puts("   Payments: #{length(payout.payments)}")
        IO.puts("   Refunds: #{length(payout.refunds)}")

        if length(payout.payments) > 0 do
          IO.puts("   Payment IDs: #{Enum.map(payout.payments, & &1.id) |> Enum.join(", ")}")
        end

        if length(payout.refunds) > 0 do
          IO.puts("   Refund IDs: #{Enum.map(payout.refunds, & &1.id) |> Enum.join(", ")}")
        end

        IO.puts("\n🔄 Relinking transactions using BalanceTransaction API...")

        # Relink all transactions
        updated_payout = WebhookHandler.relink_payout_transactions(payout)

        # Reload to get updated counts
        updated_payout = Repo.reload!(updated_payout) |> Repo.preload([:payments, :refunds])

        IO.puts("\n✅ Reprocessing complete!")
        IO.puts("\n📊 Updated transaction counts:")
        IO.puts("   Payments: #{length(updated_payout.payments)}")
        IO.puts("   Refunds: #{length(updated_payout.refunds)}")

        IO.puts(
          "   Fee Total: #{if updated_payout.fee_total, do: Money.to_string!(updated_payout.fee_total), else: "not set"}"
        )

        if length(updated_payout.payments) > 0 do
          IO.puts(
            "   Payment IDs: #{Enum.map(updated_payout.payments, & &1.id) |> Enum.join(", ")}"
          )
        end

        if length(updated_payout.refunds) > 0 do
          IO.puts(
            "   Refund IDs: #{Enum.map(updated_payout.refunds, & &1.id) |> Enum.join(", ")}"
          )
        end

        IO.puts(
          "\n📋 QuickBooks Sync Status: #{updated_payout.quickbooks_sync_status || "not set"}"
        )

        {:ok, updated_payout}
    end
  end

  def reprocess_all do
    require Logger

    IO.puts("🔄 Reprocessing all payouts...")

    # Get all payouts that might need reprocessing
    # You can add filters here if needed (e.g., only payouts without fee_total)
    payouts =
      from(p in Ledgers.Payout,
        where: not is_nil(p.stripe_payout_id),
        order_by: [desc: p.inserted_at],
        limit: 100
      )
      |> Repo.all()

    IO.puts("Found #{length(payouts)} payouts to process\n")

    results =
      Enum.map(payouts, fn payout ->
        IO.puts("Processing: #{payout.stripe_payout_id}")
        reprocess(payout.stripe_payout_id)
      end)

    successful = Enum.count(results, fn {status, _} -> status == :ok end)
    failed = length(results) - successful

    IO.puts("\n✅ Completed: #{successful} successful, #{failed} failed")
    {:ok, results}
  end
end

# If run as a script, process the payout ID from command line
if System.argv() != [] do
  [stripe_payout_id | _] = System.argv()
  ReprocessPayout.reprocess(stripe_payout_id)
else
  IO.puts("Usage: mix run reprocess_payout.exs <stripe_payout_id>")
  IO.puts("Example: mix run reprocess_payout.exs po_1SYFlzREiftrEncLDHTuRysd")
  IO.puts("\nOr use in IEx:")
  IO.puts("  iex> Code.load_file(\"reprocess_payout.exs\")")
  IO.puts("  iex> ReprocessPayout.reprocess(\"po_1SYFlzREiftrEncLDHTuRysd\")")
end
