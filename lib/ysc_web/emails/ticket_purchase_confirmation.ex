defmodule YscWeb.Emails.TicketPurchaseConfirmation do
  @moduledoc """
  Email template for ticket purchase confirmation.

  Sends a confirmation email to users after successful ticket purchase.
  """
  use MjmlEEx,
    mjml_template: "templates/ticket_purchase_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Tickets

  def get_template_name() do
    "ticket_purchase_confirmation"
  end

  def get_subject() do
    "Your tickets are confirmed! 🎫"
  end

  def event_url(event_id) do
    YscWeb.Endpoint.url() <> "/events/#{event_id}"
  end

  @doc """
  Prepares ticket purchase confirmation email data for a completed ticket order.

  ## Parameters:
  - `ticket_order`: The completed ticket order with preloaded associations

  ## Returns:
  - Map with all necessary data for the email template
  """
  def prepare_email_data(ticket_order) do
    # Ensure we have all necessary preloaded data
    ticket_order = Tickets.get_ticket_order(ticket_order.id)

    # Group tickets by tier for summary
    ticket_summaries = prepare_ticket_summaries(ticket_order.tickets)

    # Format dates and times
    event_date_time = format_event_datetime(ticket_order.event)
    purchase_date = format_datetime(ticket_order.completed_at)

    payment_date =
      if ticket_order.payment, do: format_datetime(ticket_order.payment.payment_date), else: "N/A"

    # Get payment method information
    payment_method =
      if ticket_order.payment,
        do: get_payment_method_description(ticket_order.payment),
        else: "Free"

    # Format money amounts
    total_amount = format_money(ticket_order.total_amount)

    # Prepare agenda data if available
    agenda_data = prepare_agenda_data(ticket_order.event.agendas)

    %{
      first_name: ticket_order.user.first_name || "Valued Member",
      event: %{
        title: ticket_order.event.title,
        description: ticket_order.event.description,
        start_date: ticket_order.event.start_date,
        start_time: ticket_order.event.start_time,
        location_name: ticket_order.event.location_name,
        address: ticket_order.event.address,
        age_restriction: ticket_order.event.age_restriction
      },
      event_date_time: event_date_time,
      event_url: event_url(ticket_order.event.id),
      agenda: agenda_data,
      ticket_order: %{
        reference_id: ticket_order.reference_id,
        total_amount: total_amount,
        completed_at: ticket_order.completed_at
      },
      purchase_date: purchase_date,
      payment: %{
        reference_id:
          if(ticket_order.payment, do: ticket_order.payment.reference_id, else: "N/A"),
        external_payment_id:
          if(ticket_order.payment, do: ticket_order.payment.external_payment_id, else: "N/A"),
        amount: total_amount,
        payment_date: payment_date
      },
      payment_date: payment_date,
      payment_method: payment_method,
      total_amount: total_amount,
      ticket_summaries: ticket_summaries,
      tickets:
        Enum.map(ticket_order.tickets, fn ticket ->
          %{
            reference_id: ticket.reference_id,
            ticket_tier_name: ticket.ticket_tier.name,
            status: ticket.status
          }
        end)
    }
  end

  defp prepare_ticket_summaries(tickets) do
    tickets
    |> Enum.group_by(& &1.ticket_tier_id)
    |> Enum.map(fn {_tier_id, tier_tickets} ->
      first_ticket = List.first(tier_tickets)
      quantity = length(tier_tickets)
      price_per_ticket = format_money(first_ticket.ticket_tier.price)
      total_price = format_money(calculate_tier_total(first_ticket.ticket_tier.price, quantity))

      %{
        ticket_tier_name: first_ticket.ticket_tier.name,
        quantity: quantity,
        price_per_ticket: price_per_ticket,
        total_price: total_price
      }
    end)
  end

  defp calculate_tier_total(price, quantity) do
    case price do
      %Money{amount: amount} ->
        Money.new(Decimal.mult(amount, Decimal.new(quantity)), :USD)

      _ ->
        Money.new(0, :USD)
    end
  end

  defp format_event_datetime(event) do
    case {event.start_date, event.start_time} do
      {nil, _} ->
        "TBD"

      {date, nil} ->
        Calendar.strftime(date, "%B %d, %Y")

      {date, time} ->
        # Convert DateTime to Date if needed
        date_only = if is_struct(date, DateTime), do: DateTime.to_date(date), else: date
        datetime = DateTime.new!(date_only, time, "Etc/UTC")
        # Convert to PST
        pst_datetime = DateTime.shift_zone!(datetime, "America/Los_Angeles")
        Calendar.strftime(pst_datetime, "%B %d, %Y at %I:%M %p %Z")
    end
  end

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    # Convert to PST
    pst_datetime = DateTime.shift_zone!(datetime, "America/Los_Angeles")
    Calendar.strftime(pst_datetime, "%B %d, %Y at %I:%M %p %Z")
  end

  defp get_payment_method_description(payment) do
    case payment.payment_method do
      nil ->
        "Credit Card (Stripe)"

      payment_method ->
        case payment_method.type do
          :credit_card ->
            if payment_method.last_four do
              "Credit Card ending in #{String.slice(payment_method.last_four, -4..-1)}"
            else
              "Credit Card"
            end

          :bank_account ->
            if payment_method.last_four do
              "Bank Account ending in #{String.slice(payment_method.last_four, -4..-1)}"
            else
              "Bank Account"
            end

          _ ->
            "Payment Method"
        end
    end
  end

  defp prepare_agenda_data(agendas) when is_list(agendas) and length(agendas) > 0 do
    agendas
    |> Enum.sort_by(& &1.position)
    |> Enum.map(fn agenda ->
      %{
        title: agenda.title,
        items: prepare_agenda_items(agenda.agenda_items)
      }
    end)
  end

  defp prepare_agenda_data(_), do: []

  defp prepare_agenda_items(agenda_items) when is_list(agenda_items) do
    agenda_items
    |> Enum.sort_by(& &1.position)
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      %{
        title: item.title,
        description: item.description,
        start_time: format_time(item.start_time),
        end_time: format_time(item.end_time),
        background_color: generate_agenda_color(index),
        border_color: generate_agenda_border_color(index)
      }
    end)
  end

  defp prepare_agenda_items(_), do: []

  defp format_time(nil), do: nil

  defp format_time(time) do
    Calendar.strftime(time, "%I:%M %p")
  end

  defp generate_agenda_color(index) do
    palette = [
      # Red-100
      "#FEE2E2",
      # Amber-100
      "#FEF9C3",
      # Green-100
      "#DCFCE7",
      # Blue-100
      "#DBEAFE",
      # Purple-100
      "#EDE9FE",
      # Pink-100
      "#FCE7F3",
      # Yellow-100
      "#FEF3C7",
      # Sky-100
      "#E0F2FE",
      # Emerald-100
      "#D1FAE5",
      # Indigo-100
      "#E0E7FF",
      # Rose-100
      "#FDE8E9",
      # Orange-100
      "#FFF7ED",
      # Neutral-100
      "#F3F4F6",
      # Cyan-100
      "#E8F5FF",
      # Violet-100
      "#FAE8FF"
    ]

    Enum.at(palette, rem(index, length(palette)))
  end

  defp generate_agenda_border_color(index) do
    palette = [
      # Red-400
      "#F87171",
      # Amber-400
      "#FBBF24",
      # Green-400
      "#4ADE80",
      # Blue-400
      "#60A5FA",
      # Purple-400
      "#A78BFA",
      # Pink-400
      "#FB7185",
      # Yellow-400
      "#FCD34D",
      # Sky-400
      "#38BDF8",
      # Emerald-400
      "#34D399",
      # Indigo-400
      "#818CF8",
      # Rose-400
      "#FB7185",
      # Orange-400
      "#FB923C",
      # Neutral-400
      "#A3A3A3",
      # Cyan-400
      "#22D3EE",
      # Violet-400
      "#C084FC"
    ]

    Enum.at(palette, rem(index, length(palette)))
  end

  defp format_money(%Money{amount: amount, currency: :USD}) do
    amount
    |> Decimal.to_float()
    |> :erlang.float_to_binary(decimals: 2)
    |> then(&"$#{&1}")
  end

  defp format_money(_), do: "$0.00"
end
