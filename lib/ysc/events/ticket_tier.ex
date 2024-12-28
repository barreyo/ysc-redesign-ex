defmodule Ysc.Events.TicketTier do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "ticket_tiers" do
    field :name, :string
    field :description, :string

    field :type, TicketTierType

    field :price, Money.Ecto.Composite.Type, default_currency: :USD
    field :quantity, :integer

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
      :price,
      :quantity,
      :requires_registration,
      :start_date,
      :end_date,
      :event_id,
      :lock_version
    ])
    |> validate_required([
      :name,
      :type,
      :price,
      :quantity,
      :event_id
    ])
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> validate_datetime_order()
    |> optimistic_lock(:lock_version)
    |> foreign_key_constraint(:event_id)
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
end
