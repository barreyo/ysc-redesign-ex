defmodule Ysc.Ledgers.Payment do
  use Ecto.Schema
  import Ecto.Changeset

  @reference_prefix "PMT"

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "payments" do
    field :reference_id, :string

    field :external_provider, LedgerPaymentProvider
    field :external_payment_id, :string
    field :amount, Money.Ecto.Composite.Type, default_currency: :USD

    field :status, LedgerPaymentStatus
    field :payment_date, :utc_datetime

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    timestamps()
  end

  def changeset(payment, attrs \\ {}) do
    payment
    |> cast(attrs, [
      :reference_id,
      :external_provider,
      :external_payment_id,
      :amount,
      :status,
      :payment_date,
      :user_id
    ])
    |> validate_required([
      :external_provider,
      :amount,
      :status,
      :user_id
    ])
    |> validate_length(:external_payment_id, max: 255)
    |> validate_length(:reference_id, max: 255)
    |> put_reference_id()
    |> unique_constraint(:reference_id)
    |> unique_constraint(:external_payment_id)
  end

  defp put_reference_id(changeset) do
    case get_field(changeset, :reference_id) do
      nil ->
        put_change(
          changeset,
          :reference_id,
          Ysc.ReferenceGenerator.generate_reference_id(@reference_prefix)
        )

      _ ->
        changeset
    end
  end
end
