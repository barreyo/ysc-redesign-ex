defmodule Ysc.Events.TicketDetail do
  use Ecto.Schema

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "ticket_details" do
    belongs_to :ticket, Ysc.Events.Ticket, foreign_key: :ticket_id, references: :id

    field :first_name, :string
    field :last_name, :string
    field :email, :string

    timestamps()
  end
end
