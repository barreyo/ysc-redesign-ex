defmodule Ysc.Events.TicketTier do
  use Ecto.Schema

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

    timestamps()
  end
end
