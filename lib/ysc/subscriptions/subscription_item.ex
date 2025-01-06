defmodule Ysc.Subscriptions.SubscriptionItem do
  use Ecto.Schema

  schema "subscription_items" do
    field :stripe_id, :string
    field :stripe_product_id, :string
    field :stripe_price_id, :string
    field :quantity, :integer
    belongs_to :subscription, Ysc.Subscriptions.Subscription

    timestamps(type: :utc_datetime)
  end
end
