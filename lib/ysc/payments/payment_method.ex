defmodule Ysc.Payments.PaymentMethod do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "payment_methods" do
    field :provider, PaymentMethodProvider
    field :provider_id, :string
    field :provider_customer_id, :string

    field :type, PaymentMethodType
    field :provider_type, :string

    # General field
    field :last_four, :string
    field :display_brand, :string

    # Card specific
    field :exp_month, :integer
    field :exp_year, :integer

    # Bank account specific
    field :account_type, :string
    field :routing_number, :string
    field :bank_name, :string

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    field :payload, :map, default: %{}

    timestamps()
  end
end
