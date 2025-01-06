defmodule Ysc.Subscriptions.Subscription do
  use Ecto.Schema

  schema "subscriptions" do
    field :name, :string
    field :ends_at, :utc_datetime
    field :trial_ends_at, :utc_datetime
    field :stripe_id, :string
    field :stripe_status, :string
    field :customer_id, :string
    field :customer_type, :string
    has_many :subscription_items, Ysc.Subscriptions.SubscriptionItem

    timestamps(type: :utc_datetime)
  end
end
