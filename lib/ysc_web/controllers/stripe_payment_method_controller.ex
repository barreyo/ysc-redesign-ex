defmodule Ysc.Controllers.StripePaymentMethodController do
  @moduledoc false

  use Phoenix.Controller,
    formats: [:html, :json]

  plug(Bling.Plugs.AssignCustomer)

  def finalize(conn, _params) do
    props = get_props(conn)

    if props.payment_intent || props.setup_intent do
      conn
      |> assign(:props, props)
      |> render(:finalize)
    else
      redirect(conn, to: "/")
    end
  end

  def setup_payment(conn, _params) do
    intent = Bling.Customers.create_setup_intent(conn.assigns.customer)

    conn |> json(%{client_secret: intent.client_secret})
  end

  def store_payment_method(conn, params) do
    customer = conn.assigns.customer
    payment_method_id = params["payment_method_id"]

    with {:ok, stripe_payment_method} <- retrieve_stripe_payment_method(payment_method_id),
         {:ok, payment_method} <-
           upsert_payment_method_from_stripe(customer, stripe_payment_method),
         {:ok, updated_customer} <-
           update_customer_default_payment_method(customer, payment_method.id) do
      conn
      |> assign(:customer, updated_customer)
      |> json(%{success: true, message: "Payment method stored successfully"})
    else
      {:error, :stripe_error} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to retrieve payment method from Stripe"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to store payment method", details: changeset.errors})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to store payment method", reason: reason})
    end
  end

  # Private helper functions

  defp retrieve_stripe_payment_method(payment_method_id) do
    case Stripe.PaymentMethod.retrieve(payment_method_id) do
      {:ok, payment_method} -> {:ok, payment_method}
      {:error, _} -> {:error, :stripe_error}
    end
  end

  defp upsert_payment_method_from_stripe(customer, stripe_payment_method) do
    Ysc.Payments.upsert_payment_method_from_stripe(customer, stripe_payment_method)
  end

  defp update_customer_default_payment_method(customer, payment_method_id) do
    case Ysc.Accounts.update_default_payment_method(customer, payment_method_id) do
      {:ok, updated_customer} -> {:ok, updated_customer}
      {:error, _} = error -> error
    end
  end

  defp get_props(conn) do
    router = conn.assigns.route_helpers
    customer_type = conn.params["customer_type"]
    customer_id = conn.params["customer_id"]
    finalize_url = router.bling_finalize_url(conn, :finalize, customer_type, customer_id)
    base_url = String.replace_trailing(finalize_url, "/finalize", "")

    %{
      finalize_url: finalize_url,
      base_url: base_url,
      return_to: "/",
      payment_intent: maybe_get_payment_intent(conn),
      setup_intent: maybe_get_setup_intent(conn)
    }
  end

  defp maybe_get_setup_intent(conn) do
    id = Map.get(conn.params, "setup_intent")

    with id when not is_nil(id) <- id,
         {:ok, intent} <- Stripe.SetupIntent.retrieve(id, %{}),
         true <- intent.customer == conn.assigns.customer.stripe_id do
      Map.take(intent, [:id, :client_secret, :status, :payment_method])
    else
      _ -> nil
    end
  end

  defp maybe_get_payment_intent(conn) do
    id = Map.get(conn.params, "payment_intent")

    with id when not is_nil(id) <- id,
         {:ok, intent} <- Stripe.PaymentIntent.retrieve(id, %{}),
         true <- intent.customer == conn.assigns.customer.stripe_id do
      Map.take(intent, [:id, :client_secret, :amount, :currency, :status])
    else
      _ -> nil
    end
  end
end
