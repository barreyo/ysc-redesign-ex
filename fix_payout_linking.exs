# Script to investigate and fix payout linking - run in remote IEx
# Usage: Copy and paste into IEx console

alias Ysc.Repo
alias Ysc.Ledgers
alias Ysc.Ledgers.{Payout, Payment}
import Ecto.Query

stripe_payout_id = "po_1SYFlzREiftrEncLDHTuRysd"

IO.puts("\n=== Investigating Payout Linking ===")

# 1. Get the payout
payout = Ledgers.get_payout_by_stripe_id(stripe_payout_id)

if payout do
  IO.puts("✓ Payout found: #{payout.id}")
  IO.puts("  Amount: #{inspect(payout.amount)}")

  # Reload with relations
  payout = Repo.preload(payout, [:payments, :refunds])
  IO.puts("  Current payments: #{length(payout.payments)}")
  IO.puts("  Current refunds: #{length(payout.refunds)}")

  # 2. Check join table directly
  payout_id_binary =
    case Ecto.ULID.dump(payout.id) do
      {:ok, binary} -> binary
      _ -> payout.id
    end

  join_entries =
    Repo.query!("SELECT id, payment_id FROM payout_payments WHERE payout_id = $1", [
      payout_id_binary
    ])

  IO.puts("\n  Join table entries: #{length(join_entries.rows)}")

  # 3. Check for payments that should be linked
  IO.puts("\n=== Checking for payments to link ===")

  charge_ids = [
    "ch_3SV4LmREiftrEncL009ph87v",
    "ch_3SVfblREiftrEncL0MFOc9S1",
    "ch_3SVfmlREiftrEncL1n720EYb",
    "ch_3SVxbVREiftrEncL1Mat1eDE"
  ]

  payments_to_link = []

  Enum.each(charge_ids, fn charge_id ->
    case Stripe.Charge.retrieve(charge_id) do
      {:ok, charge} ->
        payment_intent_id = charge.payment_intent
        IO.puts("\n  Charge: #{charge_id}")
        IO.puts("    Payment Intent: #{inspect(payment_intent_id)}")

        if payment_intent_id do
          payment = Ledgers.get_payment_by_external_id(payment_intent_id)

          if payment do
            IO.puts("    ✓ Found payment: #{payment.id} (#{payment.reference_id})")
            is_linked = Enum.any?(payout.payments, fn p -> p.id == payment.id end)

            if is_linked do
              IO.puts("      Already linked")
            else
              IO.puts("      ✗ NOT linked - will link now")
              payments_to_link = payments_to_link ++ [payment]
            end
          else
            IO.puts("    ✗ Payment not found for payment_intent: #{payment_intent_id}")
          end
        end

      {:error, reason} ->
        IO.puts("  ✗ Failed to get charge #{charge_id}: #{inspect(reason)}")
    end
  end)

  # 4. Link payments if found
  if length(payments_to_link) > 0 do
    IO.puts("\n=== Linking #{length(payments_to_link)} payments ===")

    Enum.each(payments_to_link, fn payment ->
      case Ledgers.link_payment_to_payout(payout, payment) do
        {:ok, _} ->
          IO.puts("  ✓ Linked payment #{payment.reference_id}")

        {:error, reason} ->
          IO.puts("  ✗ Failed to link #{payment.reference_id}: #{inspect(reason)}")
      end
    end)

    # Reload payout
    payout = Repo.reload!(payout) |> Repo.preload([:payments, :refunds])
    IO.puts("\n=== Final Status ===")
    IO.puts("  Payments linked: #{length(payout.payments)}")
    IO.puts("  Refunds linked: #{length(payout.refunds)}")
  else
    IO.puts("\n⚠️  No payments found to link")
  end
else
  IO.puts("✗ Payout not found!")
end

IO.puts("\n=== Done ===\n")
