defmodule Ysc.Bling do
  @behaviour Bling

  @impl Bling
  def can_manage_billing?(conn, customer) do
    conn.assigns.current_user.id == customer.id
  end

  @impl Bling
  def to_stripe_params(customer) do
    # pass any valid Stripe.Customer.create/2 params here
    # e.g. %{name: user.name, email: user.email}
    case customer do
      %Ysc.Accounts.User{} ->
        %{
          email: customer.email,
          name:
            "#{String.capitalize(customer.first_name)} #{String.capitalize(customer.last_name)}",
          phone: customer.phone_number
        }

      _ ->
        %{}
    end
  end

  @impl Bling
  def tax_rate_ids(_customer), do: []

  @impl Bling
  def handle_stripe_webhook_event(%Stripe.Event{} = event) do
    IO.inspect(event)

    case event.type do
      "invoice.payment_action_required" ->
        # todo: send email
        nil

      "invoice.payment.failed" ->
        # todo: send email
        nil

      _ ->
        nil
    end

    :ok
  end
end
