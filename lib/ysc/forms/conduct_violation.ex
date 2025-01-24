defmodule Ysc.Forms.ConductViolationReport do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "conduct_violation_reports" do
    field :email, :string
    field :first_name, :string
    field :last_name, :string
    field :phone, :string

    field :summary, :string

    field :status, ViolationFormStatus

    timestamps()
  end

  @doc false
  def changeset(volunteer, attrs) do
    volunteer
    |> cast(attrs, [
      :email,
      :first_name,
      :last_name,
      :phone,
      :summary,
      :status
    ])
    |> validate_required([:email, :first_name, :last_name, :phone, :summary])
    # Basic email validation
    |> validate_format(:email, ~r/@/)
  end
end
