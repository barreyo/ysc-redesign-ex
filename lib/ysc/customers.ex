defmodule Ysc.Customers do
  @moduledoc """
  The Customers context for managing customer operations with Stripe.
  """

  import Ecto.Query, warn: false
  alias Ysc.Repo
  alias Ysc.Accounts.User
  alias Ysc.Subscriptions
  alias Ysc.Payments

  @doc """
  Creates a Stripe customer for the given user.

  ## Examples

      iex> create_stripe_customer(user)
      {:ok, %Stripe.Customer{}}

  """
  def create_stripe_customer(%User{} = user) do
    customer_params = %{
      email: user.email,
      name: "#{String.capitalize(user.first_name)} #{String.capitalize(user.last_name)}",
      phone: user.phone_number
    }

    case Stripe.Customer.create(customer_params) do
      {:ok, stripe_customer} ->
        # Update user with Stripe customer ID
        Ysc.Accounts.update_user(user, %{stripe_id: stripe_customer.id}, user)
        {:ok, stripe_customer}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Gets a customer by Stripe ID.

  ## Examples

      iex> customer_from_stripe_id("cus_123")
      %User{}

      iex> customer_from_stripe_id("invalid")
      nil

  """
  def customer_from_stripe_id(stripe_id) do
    Repo.get_by(User, stripe_id: stripe_id)
  end

  @doc """
  Gets all subscriptions for a user.

  ## Examples

      iex> subscriptions(user)
      [%Subscription{}, ...]

  """
  def subscriptions(%User{} = user) do
    Subscriptions.list_subscriptions(user)
  end

  @doc """
  Checks if a user is subscribed to a specific price.

  ## Examples

      iex> subscribed_to_price?(user, "price_123")
      true

      iex> subscribed_to_price?(user, "price_456")
      false

  """
  def subscribed_to_price?(%User{} = user, price_id) do
    user
    |> subscriptions()
    |> Enum.any?(fn subscription ->
      Subscriptions.active?(subscription) and
        Enum.any?(subscription.subscription_items, fn item ->
          item.stripe_price_id == price_id
        end)
    end)
  end

  @doc """
  Creates a subscription for a user.

  ## Examples

      iex> create_subscription(user, return_url: "...", prices: [%{price: "price_123", quantity: 1}])
      {:ok, %Stripe.Subscription{}}

  """
  def create_subscription(%User{} = user, params) do
    # Ensure user has a Stripe ID
    user = ensure_stripe_customer(user)

    # Convert keyword list to map if needed
    params_map =
      if is_list(params) do
        Enum.into(params, %{})
      else
        params
      end

    case Subscriptions.create_stripe_subscription(user, params_map) do
      {:ok, stripe_subscription} ->
        {:ok, stripe_subscription}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Gets the default payment method for a user.

  ## Examples

      iex> default_payment_method(user)
      %Stripe.PaymentMethod{}

      iex> default_payment_method(user)
      nil

  """
  def default_payment_method(%User{} = user) do
    case Payments.get_default_payment_method(user) do
      nil ->
        nil

      payment_method ->
        case Stripe.PaymentMethod.retrieve(payment_method.provider_id) do
          {:ok, stripe_payment_method} -> stripe_payment_method
          {:error, _} -> nil
        end
    end
  end

  @doc """
  Gets all payment methods for a user from Stripe.

  ## Examples

      iex> payment_methods(user)
      [%Stripe.PaymentMethod{}, ...]

  """
  def payment_methods(%User{} = user) do
    case Stripe.PaymentMethod.list(%{customer: user.stripe_id, type: "card"}) do
      {:ok, %{data: payment_methods}} -> payment_methods
      {:error, _} -> []
    end
  end

  @doc """
  Creates a setup intent for a user.

  ## Examples

      iex> create_setup_intent(user, return_url: "...")
      {:ok, %Stripe.SetupIntent{}}

  """
  def create_setup_intent(%User{} = user, params \\ %{}) do
    # Ensure user has a Stripe ID
    user = ensure_stripe_customer(user)

    setup_intent_params = %{
      customer: user.stripe_id,
      payment_method_types: ["card", "us_bank_account"],
      usage: "off_session"
    }

    # Handle stripe-specific parameters
    setup_intent_params =
      if params[:stripe] && params[:stripe][:payment_method_types] do
        Map.put(
          setup_intent_params,
          :payment_method_types,
          params[:stripe][:payment_method_types]
        )
      else
        setup_intent_params
      end

    setup_intent_params =
      if params[:return_url] do
        Map.put(setup_intent_params, :return_url, params.return_url)
      else
        setup_intent_params
      end

    Stripe.SetupIntent.create(setup_intent_params)
  end

  @doc """
  Gets invoices for a user.

  ## Examples

      iex> invoices(user)
      [%Stripe.Invoice{}, ...]

  """
  def invoices(%User{} = user) do
    case Stripe.Invoice.list(%{customer: user.stripe_id}) do
      {:ok, %{data: invoices}} -> invoices
      {:error, _} -> []
    end
  end

  # Helper functions

  defp ensure_stripe_customer(%User{stripe_id: nil} = user) do
    case create_stripe_customer(user) do
      {:ok, _stripe_customer} ->
        # Reload user to get updated stripe_id
        Ysc.Accounts.get_user!(user.id)

      {:error, _error} ->
        user
    end
  end

  defp ensure_stripe_customer(%User{} = user), do: user
end
