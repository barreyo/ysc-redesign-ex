defmodule Ysc.Ledgers.Payout do
  @moduledoc """
  Payout schema and changesets.

  Defines the Payout database schema for tracking Stripe payouts
  and linking them to payments and refunds.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "payouts" do
    field :stripe_payout_id, :string
    field :amount, Money.Ecto.Composite.Type, default_currency: :USD
    field :currency, :string
    field :status, :string
    field :arrival_date, :utc_datetime
    field :description, :string
    field :metadata, :map

    # Link to the payment record created for this payout in the ledger
    belongs_to :payment, Ysc.Ledgers.Payment, foreign_key: :payment_id, references: :id

    # Many-to-many relationships with payments and refunds
    many_to_many :payments, Ysc.Ledgers.Payment,
      join_through: "payout_payments",
      join_keys: [payout_id: :id, payment_id: :id]

    many_to_many :refunds, Ysc.Ledgers.LedgerTransaction,
      join_through: "payout_refunds",
      join_keys: [payout_id: :id, refund_transaction_id: :id]

    timestamps()
  end

  def changeset(payout, attrs \\ %{}) do
    payout
    |> cast(attrs, [
      :stripe_payout_id,
      :amount,
      :currency,
      :status,
      :arrival_date,
      :description,
      :metadata,
      :payment_id
    ])
    |> validate_required([:stripe_payout_id, :amount, :currency, :status])
    |> validate_length(:stripe_payout_id, max: 255)
    |> validate_length(:description, max: 1000)
    |> unique_constraint(:stripe_payout_id)
  end
end
