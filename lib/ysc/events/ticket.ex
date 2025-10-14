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
  def changeset(ticket, attrs) do
    ticket
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
    |> validate_event_not_in_past()
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

  # Validate that the event is not in the past
  defp validate_event_not_in_past(changeset) do
    event_id = get_field(changeset, :event_id)

    if event_id do
      case Ysc.Repo.get(Ysc.Events.Event, event_id) do
        nil ->
          changeset

        event ->
          now = DateTime.utc_now()

          # Combine the date and time properly
          event_datetime =
            case {event.start_date, event.start_time} do
              {%DateTime{} = date, %Time{} = time} ->
                # Convert DateTime to NaiveDateTime, then combine with time
                naive_date = DateTime.to_naive(date)
                date_part = NaiveDateTime.to_date(naive_date)
                naive_datetime = NaiveDateTime.new!(date_part, time)
                DateTime.from_naive!(naive_datetime, "Etc/UTC")

              {date, time} when not is_nil(date) and not is_nil(time) ->
                # Handle other date/time combinations
                NaiveDateTime.new!(date, time)
                |> DateTime.from_naive!("Etc/UTC")

              _ ->
                # Fallback to just the date if time is nil
                event.start_date
            end

          if DateTime.compare(now, event_datetime) == :gt do
            add_error(
              changeset,
              :event_id,
              "cannot purchase tickets for events that have already ended"
            )
          else
            changeset
          end
      end
    else
      changeset
    end
  end
end
