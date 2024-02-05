defmodule Ysc.Accounts.SignupApplication do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "signup_applications" do
    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    field :membership_type, MembershipType
    field :membership_eligibility, {:array, MembershipEligibility}

    has_many :family_members, Ysc.Accounts.FamilyMember

    field :occupation, :string
    field :birth_date, :date

    field :address, :string
    field :country, :string
    field :city, :string
    field :postal_code, :string

    field :place_of_birth, :string
    field :citizenship, :string
    field :most_connected_nordic_country, :string

    field :link_to_scandinavia, :string
    field :lived_in_scandinavia, :string
    field :spoken_languages, :string
    field :hear_about_the_club, :string

    field :agreed_to_bylaws_at, :utc_datetime

    timestamps()
  end

  def application_changeset(application, attrs, opts \\ []) do
    application
    |> cast(attrs, [
      :membership_type,
      :membership_eligibility,
      :occupation,
      :birth_date,
      :address,
      :country,
      :city,
      :postal_code,
      :place_of_birth,
      :citizenship,
      :most_connected_nordic_country,
      :link_to_scandinavia,
      :lived_in_scandinavia,
      :spoken_languages,
      :hear_about_the_club
    ])
  end
end
