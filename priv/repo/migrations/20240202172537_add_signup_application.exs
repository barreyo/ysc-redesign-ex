defmodule Ysc.Repo.Migrations.AddSignupApplication do
  use Ecto.Migration

  def change do
    create table(:signup_applications, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true
      add :user_id, references(:users, column: :id, type: :binary_id), null: false

      add :membership_type, :string, null: false
      add :membership_eligibility, {:array, :string}, null: false
      add :occupation, :string, null: true
      add :birth_date, :date, null: false

      add :address, :string, null: false
      add :country, :string, null: false
      add :city, :string, null: false
      add :postal_code, :string, null: false

      add :place_of_birth, :string, null: false
      add :citizenship, :string, null: false

      add :most_connected_nordic_country, :string, null: false

      # Longer questions
      add :link_to_scandinavia, :text
      add :lived_in_scandinavia, :text
      add :spoken_languages, :text
      add :hear_about_the_club, :text

      add :agreed_to_bylaws_at, :utc_datetime

      timestamps()
    end

    create unique_index(:signup_applications, [:user_id])

    create table(:family_members, primary_key: false) do
      add :id, :binary_id, null: false, primary_key: true

      add :first_name, :string, null: false
      add :last_name, :string, null: false
      # Spouse or Child
      add :type, :string, null: false

      add :signup_application_id, references(:signup_applications, column: :id, type: :binary_id),
        null: false

      timestamps()
    end

    create index(:family_members, [:signup_application_id])
  end
end
