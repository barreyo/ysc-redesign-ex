defmodule Ysc.Bookings.Room do
  @moduledoc """
  Room schema and changesets.

  Defines the Room database schema, validations, and changeset functions
  for room data manipulation. Rooms can have minimum person requirements
  (e.g., family room with 2 person minimum) and maximum capacity.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "rooms" do
    field :name, :string
    field :description, :string

    # Property location (tahoe or clear_lake)
    field :property, Ysc.Bookings.BookingProperty

    # Capacity constraints
    # capacity_max: hard limit (e.g., single bed → 1)
    field :capacity_max, :integer
    # min_billable_occupancy: billing floor (e.g., family room → 2)
    # This is separate from capacity - determines minimum billing amount
    field :min_billable_occupancy, :integer, default: 1

    # Whether this is a single bed room (max 1 person)
    field :is_single_bed, :boolean, default: false

    # Bed counts
    field :single_beds, :integer, default: 0
    field :queen_beds, :integer, default: 0
    field :king_beds, :integer, default: 0

    # Active/inactive status
    field :is_active, :boolean, default: true

    # Relationships
    belongs_to :room_category, Ysc.Bookings.RoomCategory,
      foreign_key: :room_category_id,
      references: :id

    belongs_to :season, Ysc.Bookings.Season, foreign_key: :default_season_id, references: :id

    belongs_to :image, Ysc.Media.Image, foreign_key: :image_id, references: :id

    has_many :pricing_rules, Ysc.Bookings.PricingRule, foreign_key: :room_id

    timestamps()
  end

  @doc """
  Creates a changeset for the Room schema.
  """
  def changeset(room, attrs \\ %{}) do
    room
    |> cast(attrs, [
      :name,
      :description,
      :property,
      :capacity_max,
      :min_billable_occupancy,
      :is_single_bed,
      :single_beds,
      :queen_beds,
      :king_beds,
      :is_active,
      :room_category_id,
      :default_season_id,
      :image_id
    ])
    |> validate_required([
      :name,
      :property,
      :capacity_max
    ])
    |> validate_capacity_constraints()
    |> validate_single_bed_consistency()
    |> validate_length(:name, max: 255)
    |> validate_length(:description, max: 1000)
    |> validate_number(:single_beds, greater_than_or_equal_to: 0)
    |> validate_number(:queen_beds, greater_than_or_equal_to: 0)
    |> validate_number(:king_beds, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:room_category_id)
    |> foreign_key_constraint(:default_season_id)
    |> foreign_key_constraint(:image_id)
  end

  # Validates capacity constraints
  defp validate_capacity_constraints(changeset) do
    capacity_max = get_field(changeset, :capacity_max)
    min_billable = get_field(changeset, :min_billable_occupancy)

    changeset
    |> validate_number(:capacity_max, greater_than: 0, less_than_or_equal_to: 12)
    |> validate_number(:min_billable_occupancy, greater_than: 0)
    |> validate_capacity_range(capacity_max, min_billable)
  end

  # Ensures min_billable_occupancy <= capacity_max
  defp validate_capacity_range(changeset, capacity_max, min_billable)
       when not is_nil(capacity_max) and not is_nil(min_billable) do
    if min_billable > capacity_max do
      add_error(
        changeset,
        :min_billable_occupancy,
        "must be less than or equal to capacity_max"
      )
    else
      changeset
    end
  end

  defp validate_capacity_range(changeset, _capacity_max, _min_billable), do: changeset

  # Validates single bed room consistency
  # Single bed rooms must have capacity_max = 1
  defp validate_single_bed_consistency(changeset) do
    is_single_bed = get_field(changeset, :is_single_bed)
    capacity_max = get_field(changeset, :capacity_max)

    if is_single_bed && capacity_max != 1 do
      add_error(
        changeset,
        :capacity_max,
        "must be 1 for single bed rooms"
      )
    else
      changeset
    end
  end

  @doc """
  Calculates the effective (billable) number of people for pricing purposes.

  If the number of people is below the minimum billable occupancy, returns the minimum.
  The result is capped by capacity_max. This ensures rooms with minimums are charged
  correctly (e.g., family room with min_billable_occupancy=2 charges for 2 people
  even if only 1 person is assigned).

  ## Examples

      iex> room = %Room{min_billable_occupancy: 2, capacity_max: 4}
      iex> billable_people(room, 1)
      2

      iex> room = %Room{min_billable_occupancy: 2, capacity_max: 4}
      iex> billable_people(room, 3)
      3

      iex> room = %Room{min_billable_occupancy: 2, capacity_max: 4}
      iex> billable_people(room, 5)
      4
  """
  def billable_people(
        %__MODULE__{
          min_billable_occupancy: min_billable,
          capacity_max: capacity_max
        },
        num_people
      )
      when is_integer(num_people) and num_people > 0 do
    num_people
    |> max(min_billable)
    |> min(capacity_max)
  end

  def billable_people(_room, _num_people), do: nil
end
