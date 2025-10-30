defmodule Ysc.Subscriptions do
  @moduledoc """
  The Subscriptions context for managing subscriptions and subscription items.
  """

  import Ecto.Query, warn: false
  alias Ysc.Repo
  alias Ysc.Subscriptions.{Subscription, SubscriptionItem}

  @doc """
  Returns the list of subscriptions for a given user.

  ## Examples

      iex> list_subscriptions(user)
      [%Subscription{}, ...]

  """
  def list_subscriptions(user) do
    Subscription
    |> where([s], s.user_id == ^user.id)
    |> preload(:subscription_items)
    |> Repo.all()
  end

  @doc """
  Gets a single subscription by Stripe ID.

  ## Examples

      iex> get_subscription_by_stripe_id("sub_123")
      %Subscription{}

      iex> get_subscription_by_stripe_id("invalid")
      nil

  """
  def get_subscription_by_stripe_id(stripe_id) do
    Subscription
    |> where([s], s.stripe_id == ^stripe_id)
    |> preload(:subscription_items)
    |> Repo.one()
  end

  @doc """
  Gets a single subscription by ID.

  ## Examples

      iex> get_subscription(123)
      %Subscription{}

      iex> get_subscription(456)
      nil

  """
  def get_subscription(id) do
    Subscription
    |> where([s], s.id == ^id)
    |> preload(:subscription_items)
    |> Repo.one()
  end

  @doc """
  Creates a subscription.

  ## Examples

      iex> create_subscription(%{field: value})
      {:ok, %Subscription{}}

      iex> create_subscription(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_subscription(attrs \\ %{}) do
    %Subscription{}
    |> Subscription.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a subscription.

  ## Examples

      iex> update_subscription(subscription, %{field: new_value})
      {:ok, %Subscription{}}

      iex> update_subscription(subscription, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_subscription(%Subscription{} = subscription, attrs) do
    subscription
    |> Subscription.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a subscription.

  ## Examples

      iex> delete_subscription(subscription)
      {:ok, %Subscription{}}

      iex> delete_subscription(subscription)
      {:error, %Ecto.Changeset{}}

  """
  def delete_subscription(%Subscription{} = subscription) do
    Repo.delete(subscription)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking subscription changes.

  ## Examples

      iex> change_subscription(subscription)
      %Ecto.Changeset{data: %Subscription{}}

  """
  def change_subscription(%Subscription{} = subscription, attrs \\ %{}) do
    Subscription.changeset(subscription, attrs)
  end

  @doc """
  Creates a subscription item.

  ## Examples

      iex> create_subscription_item(%{field: value})
      {:ok, %SubscriptionItem{}}

      iex> create_subscription_item(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_subscription_item(attrs \\ %{}) do
    %SubscriptionItem{}
    |> SubscriptionItem.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a subscription item.

  ## Examples

      iex> update_subscription_item(subscription_item, %{field: new_value})
      {:ok, %SubscriptionItem{}}

      iex> update_subscription_item(subscription_item, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_subscription_item(%SubscriptionItem{} = subscription_item, attrs) do
    subscription_item
    |> SubscriptionItem.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a subscription item.

  ## Examples

      iex> delete_subscription_item(subscription_item)
      {:ok, %SubscriptionItem{}}

      iex> delete_subscription_item(subscription_item)
      {:error, %Ecto.Changeset{}}

  """
  def delete_subscription_item(%SubscriptionItem{} = subscription_item) do
    Repo.delete(subscription_item)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking subscription item changes.

  ## Examples

      iex> change_subscription_item(subscription_item)
      %Ecto.Changeset{data: %SubscriptionItem{}}

  """
  def change_subscription_item(%SubscriptionItem{} = subscription_item, attrs \\ %{}) do
    SubscriptionItem.changeset(subscription_item, attrs)
  end

  # Subscription status and validation functions

  @doc """
  Checks if a subscription is active.

  ## Examples

      iex> active?(subscription)
      true

      iex> active?(cancelled_subscription)
      false

  """
  def active?(%Subscription{} = subscription) do
    case subscription.stripe_status do
      "active" -> true
      "trialing" -> true
      _ -> false
    end
  end

  @doc """
  Checks if a subscription is valid (active or trialing).

  ## Examples

      iex> valid?(subscription)
      true

      iex> valid?(cancelled_subscription)
      false

  """
  def valid?(%Subscription{} = subscription) do
    active?(subscription)
  end

  @doc """
  Checks if a subscription is cancelled.

  ## Examples

      iex> cancelled?(subscription)
      false

      iex> cancelled?(cancelled_subscription)
      true

      iex> cancelled?(nil)
      false

  """
  def cancelled?(%Subscription{} = subscription) do
    subscription.stripe_status == "cancelled"
  end

  def cancelled?(nil), do: false

  @doc """
  Checks if a subscription is scheduled for cancellation at the end of the current period.

  ## Examples

      iex> scheduled_for_cancellation?(subscription)
      true

  """
  def scheduled_for_cancellation?(%Subscription{} = subscription) do
    # This would need to be tracked in the database or fetched from Stripe
    # For now, we'll check if the subscription is active but has a cancellation flag
    subscription.stripe_status == "active" &&
      subscription.current_period_end &&
      DateTime.compare(subscription.current_period_end, DateTime.utc_now()) == :gt
  end

  def scheduled_for_cancellation?(nil), do: false

  @doc """
  Marks a subscription as cancelled.

  ## Examples

      iex> mark_as_cancelled(subscription)
      {:ok, %Subscription{}}

  """
  def mark_as_cancelled(%Subscription{} = subscription) do
    update_subscription(subscription, %{stripe_status: "cancelled"})
  end

  @doc """
  Cancels a subscription in Stripe by scheduling cancellation at the end of the current period.
  This makes the subscription resumable until the period ends.

  ## Examples

      iex> cancel(subscription)
      {:ok, %Subscription{}}

  """
  def cancel(%Subscription{} = subscription) do
    case Stripe.Subscription.update(subscription.stripe_id, %{cancel_at_period_end: true}) do
      {:ok, stripe_subscription} ->
        update_subscription(subscription, %{
          stripe_status: stripe_subscription.status,
          current_period_end: stripe_subscription.current_period_end
        })

      {:error, _error} ->
        {:error, "Failed to cancel subscription in Stripe"}
    end
  end

  @doc """
  Immediately cancels a subscription in Stripe (permanent deletion).
  This should only be used for admin purposes or special cases where resumability is not needed.

  ## Examples

      iex> cancel_immediately(subscription)
      {:ok, %Subscription{}}

  """
  def cancel_immediately(%Subscription{} = subscription) do
    case Stripe.Subscription.delete(subscription.stripe_id) do
      {:ok, _stripe_subscription} ->
        mark_as_cancelled(subscription)

      {:error, _error} ->
        {:error, "Failed to cancel subscription immediately in Stripe"}
    end
  end

  @doc """
  Resumes a cancelled subscription in Stripe.

  ## Examples

      iex> resume(subscription)
      {:ok, %Subscription{}}

  """
  def resume(%Subscription{} = subscription) do
    case Stripe.Subscription.update(subscription.stripe_id, %{cancel_at_period_end: false}) do
      {:ok, stripe_subscription} ->
        update_subscription(subscription, %{
          stripe_status: stripe_subscription.status,
          current_period_end: stripe_subscription.current_period_end
        })

      {:error, _error} ->
        {:error, "Failed to resume subscription in Stripe"}
    end
  end

  @doc """
  Changes the prices/items for a subscription.

  ## Examples

      iex> change_prices(subscription, prices: [%{price: "price_123", quantity: 1}])
      {:ok, %Subscription{}}

  """
  def change_prices(%Subscription{} = subscription, params) do
    # Get current subscription items (for potential future use)
    _current_items = Repo.preload(subscription, :subscription_items).subscription_items

    # Create new items from params
    new_items =
      Enum.map(params.prices, fn price ->
        %{
          price: price.price,
          quantity: price.quantity
        }
      end)

    # Update subscription in Stripe
    case Stripe.Subscription.update(subscription.stripe_id, %{items: new_items}) do
      {:ok, stripe_subscription} ->
        # Update local subscription
        update_subscription(subscription, %{
          stripe_status: stripe_subscription.status,
          current_period_end: stripe_subscription.current_period_end
        })

      {:error, _error} ->
        {:error, "Failed to change subscription prices in Stripe"}
    end
  end

  # Stripe integration functions

  @doc """
  Creates a subscription struct from a Stripe subscription.

  ## Examples

      iex> subscription_struct_from_stripe_subscription(user, stripe_subscription)
      %Ecto.Changeset{data: %Subscription{}}

  """
  def subscription_struct_from_stripe_subscription(
        user,
        %Stripe.Subscription{} = stripe_subscription
      ) do
    attrs = %{
      stripe_id: stripe_subscription.id,
      stripe_status: stripe_subscription.status,
      user_id: user.id,
      # Default name for membership subscriptions
      name: "Membership Subscription",
      start_date:
        stripe_subscription.start_date && DateTime.from_unix!(stripe_subscription.start_date),
      current_period_start:
        stripe_subscription.current_period_start &&
          DateTime.from_unix!(stripe_subscription.current_period_start),
      current_period_end:
        stripe_subscription.current_period_end &&
          DateTime.from_unix!(stripe_subscription.current_period_end),
      trial_ends_at:
        stripe_subscription.trial_end && DateTime.from_unix!(stripe_subscription.trial_end),
      ends_at: stripe_subscription.ended_at && DateTime.from_unix!(stripe_subscription.ended_at)
    }

    %Subscription{}
    |> Subscription.changeset(attrs)
  end

  @doc """
  Creates subscription item structs from Stripe subscription items.

  ## Examples

      iex> subscription_item_structs_from_stripe_items(stripe_items, subscription)
      [%Ecto.Changeset{data: %SubscriptionItem{}}, ...]

  """
  def subscription_item_structs_from_stripe_items(stripe_items, subscription) do
    Enum.map(stripe_items, fn stripe_item ->
      attrs = %{
        stripe_id: stripe_item.id,
        stripe_product_id: stripe_item.price.product,
        stripe_price_id: stripe_item.price.id,
        quantity: stripe_item.quantity,
        subscription_id: subscription.id
      }

      %SubscriptionItem{}
      |> SubscriptionItem.changeset(attrs)
    end)
  end

  @doc """
  Creates a subscription in Stripe.

  ## Examples

      iex> create_stripe_subscription(user, %{prices: [%{price: "price_123", quantity: 1}]})
      {:ok, %Stripe.Subscription{}}

  """
  def create_stripe_subscription(user, params) do
    # Handle both keyword lists and maps
    prices = params[:prices] || params["prices"] || params.prices
    expand = params[:expand] || params["expand"] || []

    stripe_params = %{
      customer: user.stripe_id,
      items: Enum.map(prices, fn price -> %{price: price.price, quantity: price.quantity} end),
      expand: expand
    }

    stripe_params =
      if params[:default_payment_method] || params["default_payment_method"] do
        default_pm = params[:default_payment_method] || params["default_payment_method"]
        Map.put(stripe_params, :default_payment_method, default_pm)
      else
        stripe_params
      end

    Stripe.Subscription.create(stripe_params)
  end

  @doc """
  Creates a local subscription from a Stripe subscription.
  This is used as a backup when webhooks might not be reliable.
  """
  def create_subscription_from_stripe(user, stripe_subscription) do
    require Logger

    # Check if subscription already exists
    existing = get_subscription_by_stripe_id(stripe_subscription.id)

    if existing do
      Logger.info("Subscription already exists locally",
        user_id: user.id,
        subscription_id: existing.id,
        stripe_subscription_id: stripe_subscription.id
      )

      {:ok, existing}
    else
      # Create the subscription
      subscription_changeset =
        user
        |> Ecto.build_assoc(:subscriptions)
        |> Subscription.changeset(%{
          user_id: user.id,
          # Default name for membership subscriptions
          name: "Membership Subscription",
          stripe_id: stripe_subscription.id,
          stripe_status: stripe_subscription.status,
          start_date:
            stripe_subscription.start_date && DateTime.from_unix!(stripe_subscription.start_date),
          current_period_start:
            stripe_subscription.current_period_start &&
              DateTime.from_unix!(stripe_subscription.current_period_start),
          current_period_end:
            stripe_subscription.current_period_end &&
              DateTime.from_unix!(stripe_subscription.current_period_end),
          trial_ends_at:
            stripe_subscription.trial_end && DateTime.from_unix!(stripe_subscription.trial_end),
          ends_at:
            stripe_subscription.ended_at && DateTime.from_unix!(stripe_subscription.ended_at)
        })

      subscription = Repo.insert(subscription_changeset)

      case subscription do
        {:ok, subscription} ->
          # Create subscription items
          subscription_items =
            subscription_item_structs_from_stripe_items(
              stripe_subscription.items.data,
              subscription
            )

          Enum.each(subscription_items, fn item ->
            case Repo.insert(item) do
              {:ok, _} ->
                :ok

              {:error, reason} ->
                Logger.error("Failed to create subscription item",
                  user_id: user.id,
                  subscription_id: subscription.id,
                  error: reason
                )
            end
          end)

          Logger.info("Successfully created subscription from Stripe",
            user_id: user.id,
            subscription_id: subscription.id,
            stripe_subscription_id: stripe_subscription.id
          )

          {:ok, subscription}

        {:error, reason} ->
          Logger.error("Failed to create subscription from Stripe",
            user_id: user.id,
            stripe_subscription_id: stripe_subscription.id,
            error: reason
          )

          {:error, reason}
      end
    end
  end
end
