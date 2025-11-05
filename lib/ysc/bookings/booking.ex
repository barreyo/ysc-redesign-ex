defmodule Ysc.Bookings.Booking do
  @moduledoc """
  Booking schema and changesets.

  Represents a room booking with check-in and check-out dates.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.ReferenceGenerator

  @reference_prefix "BKG"

  @derive {
    Flop.Schema,
    filterable: [:property, :booking_mode],
    sortable: [
      :reference_id,
      :checkin_date,
      :checkout_date,
      :guests_count,
      :property,
      :booking_mode,
      :inserted_at
    ],
    default_limit: 50,
    max_limit: 200,
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    },
    adapter_opts: [
      join_fields: [
        user_first: [
          binding: :user,
          field: :first_name,
          ecto_type: :string
        ],
        user_last: [
          binding: :user,
          field: :last_name,
          ecto_type: :string
        ],
        user_email: [
          binding: :user,
          field: :email,
          ecto_type: :string
        ]
      ],
      compound_fields: [
        user_name: [:user_first, :user_last]
      ]
    ]
  }

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "bookings" do
    field :reference_id, :string
    field :checkin_date, :date
    field :checkout_date, :date
    field :guests_count, :integer, default: 1
    field :children_count, :integer, default: 0
    field :property, Ysc.Bookings.BookingProperty
    field :booking_mode, Ysc.Bookings.BookingMode
    belongs_to :room, Ysc.Bookings.Room, foreign_key: :room_id, references: :id
    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    timestamps()
  end

  @spec changeset(
          {map(),
           %{
             optional(atom()) =>
               atom()
               | {:array | :assoc | :embed | :in | :map | :parameterized | :supertype | :try,
                  any()}
           }}
          | %{
              :__struct__ => atom() | %{:__changeset__ => any(), optional(any()) => any()},
              optional(atom()) => any()
            }
        ) :: Ecto.Changeset.t()
  @doc """
  Creates a changeset for the Booking schema.
  """
  def changeset(booking, attrs \\ %{}, opts \\ []) do
    booking
    |> cast(attrs, [
      :reference_id,
      :checkin_date,
      :checkout_date,
      :guests_count,
      :children_count,
      :property,
      :booking_mode,
      :room_id,
      :user_id
    ])
    |> validate_required([:checkin_date, :checkout_date, :property, :booking_mode, :user_id])
    |> generate_reference_id()
    |> infer_booking_mode()
    |> validate_date_range()
    |> validate_booking_rules(opts)
    |> unique_constraint(:reference_id)
    |> foreign_key_constraint(:room_id)
    |> foreign_key_constraint(:user_id)
  end

  defp generate_reference_id(changeset) do
    case get_change(changeset, :reference_id) do
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

  # Infer booking_mode from room_id if not provided
  defp infer_booking_mode(changeset) do
    booking_mode = get_field(changeset, :booking_mode)
    room_id = get_field(changeset, :room_id)

    cond do
      not is_nil(booking_mode) ->
        changeset

      is_nil(room_id) ->
        # No room = buyout
        put_change(changeset, :booking_mode, :buyout)

      true ->
        # Has room = room booking
        put_change(changeset, :booking_mode, :room)
    end
  end

  defp validate_booking_rules(changeset, opts) do
    user = opts[:user] || (get_field(changeset, :user_id) && get_user_from_changeset(changeset))
    Ysc.Bookings.BookingValidator.validate(changeset, user: user)
  end

  defp get_user_from_changeset(changeset) do
    alias Ysc.Repo
    alias Ysc.Accounts.User

    user_id = get_field(changeset, :user_id)

    if user_id do
      Repo.get(User, user_id) |> Repo.preload(:subscriptions)
    else
      nil
    end
  end

  defp validate_date_range(changeset) do
    checkin_date = get_field(changeset, :checkin_date)
    checkout_date = get_field(changeset, :checkout_date)

    if checkin_date && checkout_date do
      if Date.compare(checkout_date, checkin_date) == :lt do
        add_error(changeset, :checkout_date, "must be on or after check-in date")
      else
        changeset
      end
    else
      changeset
    end
  end
end
