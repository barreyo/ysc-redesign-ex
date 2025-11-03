defmodule Ysc.Events.TicketTier do
  @moduledoc """
  Ticket tier schema and changesets.

  Defines the TicketTier database schema, validations, and changeset functions
  for ticket tier data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "ticket_tiers" do
    field :name, :string
    field :description, :string

    field :type, Ysc.Events.TicketTierType

    field :price, Money.Ecto.Composite.Type, default_currency: :USD
    field :quantity, :integer
    field :unlimited_quantity, :boolean, virtual: true

    # If this is set all the tickets require to have
    # a registration attached to them
    field :requires_registration, :boolean

    # Set a start and end date for the ticket tier
    # when it goes on sale and when the sale ends
    field :start_date, :utc_datetime
    field :end_date, :utc_datetime

    belongs_to :event, Ysc.Events.Event, foreign_key: :event_id, references: :id

    field :lock_version, :integer, default: 1

    timestamps()
  end

  @doc """
  Creates a changeset for the TicketTier schema.
  """
  def changeset(ticket_tier, attrs \\ %{}) do
    ticket_tier
    |> cast(attrs, [
      :name,
      :description,
      :type,
      :quantity,
      :unlimited_quantity,
      :price,
      :requires_registration,
      :start_date,
      :end_date,
      :event_id,
      :lock_version
    ])
    |> validate_required([
      :name,
      :type,
      :event_id
    ])
    |> enforce_free_price()
    |> validate_required_price()
    |> validate_quantity()
    |> validate_datetime_order()
    |> validate_money(:price)
    |> validate_event_capacity()
    |> optimistic_lock(:lock_version)
    |> foreign_key_constraint(:event_id)
  end

  # Custom validation for price field - required for paid types only
  # Donation types allow nil price (user sets arbitrary amount)
  defp validate_required_price(changeset) do
    type = get_field(changeset, :type)
    price = get_field(changeset, :price)

    case {type, price} do
      {:free, _} -> changeset
      {"free", _} -> changeset
      {:donation, _} -> changeset
      {"donation", _} -> changeset
      {_, nil} -> add_error(changeset, :price, "is required for paid tickets")
      {_, ""} -> add_error(changeset, :price, "is required for paid tickets")
      _ -> changeset
    end
  end

  # Ensure FREE ticket tiers always have price set to 0 USD
  defp enforce_free_price(changeset) do
    case get_field(changeset, :type) do
      :free -> put_change(changeset, :price, Money.new(0, :USD))
      "free" -> put_change(changeset, :price, Money.new(0, :USD))
      _ -> changeset
    end
  end

  # Custom validation for quantity field - must be positive when present, nil means infinite
  # Convert 0 to nil to treat it as unlimited
  defp validate_quantity(changeset) do
    quantity = get_field(changeset, :quantity)

    case quantity do
      nil ->
        changeset

      0 ->
        put_change(changeset, :quantity, nil)

      quantity when is_integer(quantity) and quantity > 0 ->
        changeset

      quantity when is_integer(quantity) and quantity < 0 ->
        add_error(changeset, :quantity, "must be greater than or equal to 0")

      _ ->
        changeset
    end
  end

  # Custom validation for money field
  defp validate_money(changeset, field) do
    validate_change(changeset, field, fn _field, value ->
      case value do
        %Money{currency: :USD} = money when money.amount >= 0 ->
          []

        %Money{currency: currency} when currency != :USD ->
          [{field, "must be in USD"}]

        %Money{amount: amount} when amount < 0 ->
          [{field, "must be greater than or equal to 0"}]

        nil ->
          []

        _ ->
          [{field, "invalid money format"}]
      end
    end)
  end

  # Private function to validate that end_date is after start_date if both are present
  defp validate_datetime_order(changeset) do
    case {get_field(changeset, :start_date), get_field(changeset, :end_date)} do
      {start_date, end_date} when not is_nil(start_date) and not is_nil(end_date) ->
        if DateTime.compare(end_date, start_date) == :gt do
          changeset
        else
          add_error(changeset, :end_date, "must be after start date")
        end

      _ ->
        changeset
    end
  end

  # Validate that the total capacity across all ticket tiers doesn't exceed event max_attendees
  defp validate_event_capacity(changeset) do
    event_id = get_field(changeset, :event_id)
    quantity = get_field(changeset, :quantity)

    # Skip validation if no event_id or quantity is nil (unlimited)
    if event_id && quantity do
      # Get the event to check max_attendees
      case Ysc.Repo.get(Ysc.Events.Event, event_id) do
        nil ->
          changeset

        event when is_nil(event.max_attendees) ->
          # No max_attendees limit set, allow any quantity
          changeset

        event ->
          # Calculate total capacity across all ticket tiers for this event
          total_capacity = calculate_total_event_capacity(event_id, changeset)

          if total_capacity > event.max_attendees do
            add_error(
              changeset,
              :quantity,
              "would exceed event capacity of #{event.max_attendees} attendees. Total capacity would be #{total_capacity}"
            )
          else
            changeset
          end
      end
    else
      changeset
    end
  end

  # Calculate total capacity across all ticket tiers for an event
  defp calculate_total_event_capacity(event_id, current_changeset) do
    # Get all existing ticket tiers for this event
    existing_tiers = Ysc.Events.list_ticket_tiers_for_event(event_id)

    # Calculate total from existing tiers
    existing_total =
      existing_tiers
      |> Enum.map(& &1.quantity)
      |> Enum.reject(&is_nil/1)
      |> Enum.sum()

    # Add the quantity from the current changeset (if it's an update, we need to handle it properly)
    current_quantity = get_field(current_changeset, :quantity)
    current_tier_id = get_field(current_changeset, :id)

    # If this is an update to an existing tier, we need to subtract the old quantity first
    adjusted_total =
      if current_tier_id do
        # Find the existing tier being updated
        existing_tier = Enum.find(existing_tiers, &(&1.id == current_tier_id))

        if existing_tier && existing_tier.quantity do
          # Subtract the old quantity and add the new one
          existing_total - existing_tier.quantity + (current_quantity || 0)
        else
          existing_total + (current_quantity || 0)
        end
      else
        # This is a new tier, just add the quantity
        existing_total + (current_quantity || 0)
      end

    adjusted_total
  end
end
