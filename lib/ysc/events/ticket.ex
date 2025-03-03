defmodule Ysc.Events.Ticket do
  use Ecto.Schema

  import Ecto.Changeset

  alias Ysc.ReferenceGenerator

  @reference_prefix "TKT"

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

  @doc """
  Changeset for the ticket with validations.
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :reference_id,
      :event_id,
      :ticket_tier_id,
      :user_id,
      :status,
      :payment_id,
      :expires_at
    ])
    |> validate_required([
      :event_id,
      :ticket_tier_id,
      :user_id,
      :expires_at
    ])
    |> put_reference_id()
    |> unique_constraint(:reference_id)
  end

  defp put_reference_id(changeset) do
    case get_field(changeset, :reference_id) do
      nil ->
        put_change(
          changeset,
          :reference_id,
          ReferenceGenerator.generate_reference_id(@reference_prefix)
        )

      _ ->
        changeset
    end
  end
end
