# Script to investigate payout linking issue - run in remote environment
# Usage: fly -c etc/fly/fly-sandbox.toml ssh console --pty -C "/app/bin/ysc remote"
# Then: Code.eval_file("investigate_payout_remote.exs")

alias Ysc.Repo
alias Ysc.Ledgers
alias Ysc.Ledgers.{Payout, Payment}
import Ecto.Query

payout_id = "01KB3YWN392VBTTXC7AGA9S8Y0"
stripe_payout_id = "po_1SYFlzREiftrEncLDHTuRysd"

IO.puts("\n=== Investigating Payout ===")
IO.puts("Payout ID: #{payout_id}")
IO.puts("Stripe Payout ID: #{stripe_payout_id}\n")

# 1. Get the payout record
payout = Ledgers.get_payout_by_stripe_id(stripe_payout_id)

if payout do
  IO.puts("✓ Payout found in database")
  IO.puts("  ID: #{payout.id}")
  IO.puts("  Amount: #{inspect(payout.amount)}")
  IO.puts("  Status: #{payout.status}")
  IO.puts("  Arrival Date: #{inspect(payout.arrival_date)}")
  IO.puts("  QuickBooks Sync Status: #{payout.quickbooks_sync_status}")
  IO.puts("  Payment ID (payout's own payment): #{inspect(payout.payment_id)}")

  # 2. Check linked payments via join table
  payout_with_relations = Repo.preload(payout, [:payments, :refunds])

  IO.puts("\n=== Linked Payments (via payout_payments join table) ===")
  IO.puts("Count: #{length(payout_with_relations.payments)}")

  Enum.each(payout_with_relations.payments, fn payment ->
    IO.puts("  - Payment ID: #{payment.id}")
    IO.puts("    Reference ID: #{payment.reference_id}")
    IO.puts("    Amount: #{inspect(payment.amount)}")
    IO.puts("    External Payment ID: #{payment.external_payment_id}")
    IO.puts("    User ID: #{inspect(payment.user_id)}")
    IO.puts("    QB Sync Status: #{payment.quickbooks_sync_status}")
  end)

  IO.puts("\n=== Linked Refunds (via payout_refunds join table) ===")
  IO.puts("Count: #{length(payout_with_relations.refunds)}")

  Enum.each(payout_with_relations.refunds, fn refund ->
    IO.puts("  - Refund ID: #{refund.id}")
    IO.puts("    Reference ID: #{refund.reference_id}")
    IO.puts("    Amount: #{inspect(refund.amount)}")
  end)

  # 3. Check payout_payments join table directly
  IO.puts("\n=== Checking payout_payments join table directly ===")

  payout_id_binary =
    case Ecto.ULID.dump(payout.id) do
      {:ok, binary} -> binary
      _ -> payout.id
    end

  join_table_entries =
    from(pp in "payout_payments",
      where: pp.payout_id == ^payout_id_binary
    )
    |> Repo.all()

  IO.puts("Join table entries: #{length(join_table_entries)}")

  Enum.each(join_table_entries, fn entry ->
    IO.puts("  - Join ID: #{inspect(entry.id)}")
    IO.puts("    Payment ID (binary): #{inspect(entry.payment_id)}")
  end)

  # 4. Check if payments exist with the charge IDs from Stripe
  IO.puts("\n=== Checking for payments that should be linked ===")
  IO.puts("Expected charges from Stripe:")
  IO.puts("  - ch_3SV4LmREiftrEncL009ph87v (Subscription, $45.00)")
  IO.puts("  - ch_3SVfblREiftrEncL0MFOc9S1 (Booking BKG-251120-FKKJD, $300.00)")
  IO.puts("  - ch_3SVfmlREiftrEncL1n720EYb (Booking BKG-251120-275RV, $50.00)")
  IO.puts("  - ch_3SVxbVREiftrEncL1Mat1eDE (Booking BKG-251121-H9RE0, $100.00)")

  # Get charges from Stripe to find payment_intent IDs
  IO.puts("\n=== Fetching charges from Stripe to find payment_intent IDs ===")

  charge_ids = [
    "ch_3SV4LmREiftrEncL009ph87v",
    "ch_3SVfblREiftrEncL0MFOc9S1",
    "ch_3SVfmlREiftrEncL1n720EYb",
    "ch_3SVxbVREiftrEncL1Mat1eDE"
  ]

  Enum.each(charge_ids, fn charge_id ->
    IO.puts("\n  Processing charge: #{charge_id}")

    case Stripe.Charge.retrieve(charge_id) do
      {:ok, charge} ->
        payment_intent_id = charge.payment_intent
        IO.puts("    Payment Intent ID: #{inspect(payment_intent_id)}")

        if payment_intent_id do
          # Find payment by external_payment_id (payment intent ID)
          payment = Ledgers.get_payment_by_external_id(payment_intent_id)

          if payment do
            IO.puts("    ✓ Found payment:")
            IO.puts("      Payment ID: #{payment.id}")
            IO.puts("      Reference ID: #{payment.reference_id}")
            IO.puts("      Amount: #{inspect(payment.amount)}")
            IO.puts("      External Payment ID: #{payment.external_payment_id}")
            IO.puts("      User ID: #{inspect(payment.user_id)}")

            # Check if already linked
            is_linked = Enum.any?(payout_with_relations.payments, fn p -> p.id == payment.id end)

            if is_linked do
              IO.puts("      ✓ Already linked to payout")
            else
              IO.puts("      ✗ NOT linked to payout - this is the issue!")
            end
          else
            IO.puts(
              "    ✗ Payment NOT found in database for payment_intent: #{payment_intent_id}"
            )

            IO.puts("      This payment may not have been created when the charge occurred.")
          end
        else
          IO.puts("    ✗ Charge has no payment_intent_id")
        end

      {:error, reason} ->
        IO.puts("    ✗ Failed to retrieve charge from Stripe: #{inspect(reason)}")
    end
  end)

  # 5. Summary
  IO.puts("\n=== Summary ===")
  IO.puts("Payout has #{length(payout_with_relations.payments)} payments linked")
  IO.puts("Payout has #{length(payout_with_relations.refunds)} refunds linked")

  if length(payout_with_relations.payments) == 0 && length(payout_with_relations.refunds) == 0 do
    IO.puts("\n⚠️  ISSUE: Payout has no linked transactions!")
    IO.puts("This suggests link_payout_transactions/2 may not have run successfully,")
    IO.puts("or the payments/refunds don't exist in the database.")
    IO.puts("\nTo fix: Re-run link_payout_transactions manually or check webhook logs.")
  end
else
  IO.puts("✗ Payout not found in database!")
  IO.puts("  The payout may have been deleted or never created.")
  IO.puts("  Check webhook logs for 'payout.paid' event processing.")
end

IO.puts("\n=== Done ===\n")
