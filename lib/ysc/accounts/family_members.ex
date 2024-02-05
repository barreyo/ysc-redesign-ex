defmodule Ysc.Accounts.FamilyMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "family_members" do
    field :first_name, :string
    field :last_name, :string
    field :type, FamilyMemberType

    belongs_to :signup_application, Ysc.Accounts.SignupApplication,
      foreign_key: :signup_application_id,
      references: :id

    timestamps()
  end

  def family_member_changeset(family_member, attrs, opts \\ []) do
    family_member
    |> cast(attrs, [:first_name, :last_name, :type])
    |> validate_length(:first_name, min: 1, max: 160)
    |> validate_length(:last_name, min: 1, max: 160)
    |> validate_required([:first_name, :last_name, :type])
  end
end
