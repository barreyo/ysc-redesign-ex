defmodule Ysc.Repo.Migrations.AddSubscriptionIndexes do
  use Ecto.Migration

  def change do
    # Add index for customer_id lookups (used in user association)
    create index(:subscriptions, [:customer_id, :customer_type])

    # Add index for active subscription queries
    create index(:subscriptions, [:customer_id, :stripe_status])

    # Add index for subscription_items lookups
    create index(:subscription_items, [:subscription_id])
  end
end
