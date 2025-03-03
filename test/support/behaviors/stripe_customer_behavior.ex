defmodule Stripe.CustomerBehaviour do
  @callback retrieve(String.t(), keyword()) ::
              {:ok, Stripe.Customer.t()} | {:error, Stripe.Error.t()}
  @callback update(String.t(), map(), keyword()) ::
              {:ok, Stripe.Customer.t()} | {:error, Stripe.Error.t()}
end
