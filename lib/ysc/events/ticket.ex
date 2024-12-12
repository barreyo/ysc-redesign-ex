defmodule Ysc.Events.Ticket do
  use Ecto.Schema

  @reference_prefix "EVT"

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "tickets" do
    field :reference_id, :string

    belongs_to :event, Ysc.Events.Event, foreign_key: :event_id, references: :id
    belongs_to :ticket_tier, Ysc.Events.TicketTier, foreign_key: :ticket_tier_id, references: :id
    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    field :status, TicketStatus

    belongs_to :payment, Ysc.Payments.Payment, foreign_key: :payment_id, references: :id

    field :expires_at, :utc_datetime

    timestamps()
  end
end
