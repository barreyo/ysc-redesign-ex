# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Ysc.Repo.insert!(%Ysc.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Ysc.Repo
alias Ysc.Accounts.User
alias Ysc.SiteSettings.SiteSetting

# Default settings
Repo.insert!(
  SiteSetting.site_setting_changeset(%SiteSetting{}, %{
    group: "socials",
    name: "instagram",
    value: "https://www.instagram.com/theysc"
  }),
  on_conflict: :nothing
)

Repo.insert!(
  SiteSetting.site_setting_changeset(%SiteSetting{}, %{
    group: "socials",
    name: "facebook",
    value: "https://www.facebook.com/YoungScandinaviansClub/"
  }),
  on_conflict: :nothing
)

first_names = [
  "Karl",
  "Erik",
  "Lars",
  "Anders",
  "Per",
  "Mikael",
  "Johan",
  "Olof",
  "Nils",
  "Jan",
  "Maria",
  "Elisabeth",
  "Anna",
  "Kristina",
  "Margareta",
  "Eva",
  "Linnéa",
  "Karin",
  "Birgitta",
  "Marie"
]

last_names = [
  "Andersson",
  "Johansson",
  "Karlsson",
  "Nilsson",
  "Eriksson",
  "Larsson",
  "Olsson",
  "Persson",
  "Svensson",
  "Gustafsson",
  "Pettersson",
  "Jonsson",
  "Jansson",
  "Hansson",
  "Bengtsson",
  "Jönsson",
  "Lindberg",
  "Berg",
  "Lind",
  "Lundgren",
  "Lindgren",
  "Sandberg",
  "Eklund"
]

countries = [
  "SE",
  "NO",
  "FI",
  "IS",
  "DK"
]

n_approved_users = 9
n_pending_users = 5
n_rejected_users = 3
n_deleted_users = 2

admin_user =
  User.registration_changeset(%User{}, %{
    email: "admin@ysc.org",
    password: "very_secure_password",
    role: :admin,
    state: :active,
    first_name: "Admin",
    last_name: "User",
    phone_number: "+14159009009",
    most_connected_country: countries |> Enum.shuffle() |> hd,
    confirmed_at: DateTime.utc_now(),
    registration_form: %{
      membership_type: "family",
      membership_eligibility: ["citizen_of_scandinavia", "born_in_scandinavia"],
      occupation: "Plumber",
      birth_date: "1900-01-01",
      address: "Dance St 2",
      country: "USA",
      city: "Dance Town",
      region: "CA",
      postal_code: "94700",
      place_of_birth: "Norway",
      citizenship: "USA",
      most_connected_nordic_country: "Norway",
      link_to_scandinavia: "Love it!",
      lived_in_scandinavia: "For a few seconds.",
      spoken_languages: "English and German",
      hear_about_the_club: "On internet",
      agreed_to_bylaws: "true",
      agreed_to_bylaws_at: DateTime.utc_now(),
      started: DateTime.utc_now(),
      completed: DateTime.utc_now(),
      browser_timezone: "America/Los_Angeles"
    }
  })

admin_user =
  Repo.insert!(
    admin_user,
    on_conflict: :nothing
  )

Enum.each(0..n_approved_users, fn n ->
  membership_type =
    if rem(n, 2) == 0 do
      "single"
    else
      "family"
    end

  last_name = last_names |> Enum.shuffle() |> hd

  fam_members =
    if membership_type == "family" do
      [
        %{
          first_name: first_names |> Enum.shuffle() |> hd,
          last_name: last_name,
          birth_date: "1990-06-06",
          type: "spouse"
        },
        %{
          first_name: first_names |> Enum.shuffle() |> hd,
          last_name: last_name,
          birth_date: "1999-08-08",
          type: "child"
        }
      ]
    else
      []
    end

  first_name = first_names |> Enum.shuffle() |> hd

  regular_user =
    User.registration_changeset(%User{}, %{
      email: String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org"),
      password: "very_secure_password",
      role: :member,
      state: :active,
      first_name: first_name,
      last_name: last_name,
      phone_number: "+1415900900#{n}",
      confirmed_at: DateTime.utc_now(),
      most_connected_country: countries |> Enum.shuffle() |> hd,
      family_members: fam_members,
      registration_form: %{
        membership_type: membership_type,
        membership_eligibility: ["citizen_of_scandinavia", "born_in_scandinavia"],
        occupation: "Plumber",
        birth_date: "1900-01-01",
        address: "Dance St 2",
        country: "USA",
        city: "Dance Town",
        region: "CA",
        postal_code: "94700",
        place_of_birth: "Sweden",
        citizenship: "USA",
        most_connected_nordic_country: "Sweden",
        link_to_scandinavia: "Love it!",
        lived_in_scandinavia: "For a few seconds.",
        spoken_languages: "English and German",
        hear_about_the_club: "On internet",
        agreed_to_bylaws: "true",
        agreed_to_bylaws_at: DateTime.utc_now(),
        started: DateTime.utc_now(),
        completed: DateTime.utc_now(),
        browser_timezone: "America/Los_Angeles",
        reviewed_at: DateTime.utc_now(),
        review_outcome: "approved",
        reviewed_by_user_id: admin_user.id
      }
    })

  Repo.insert!(
    regular_user,
    on_conflict: :nothing
  )
end)

Enum.each(0..n_pending_users, fn n ->
  membership_type =
    if rem(n, 2) == 0 do
      "single"
    else
      "family"
    end

  last_name = last_names |> Enum.shuffle() |> hd

  fam_members =
    if membership_type == "family" do
      [
        %{
          first_name: first_names |> Enum.shuffle() |> hd,
          last_name: last_name,
          birth_date: "1990-06-06",
          type: "spouse"
        },
        %{
          first_name: first_names |> Enum.shuffle() |> hd,
          last_name: last_name,
          birth_date: "1999-08-08",
          type: "child"
        }
      ]
    else
      []
    end

  first_name = first_names |> Enum.shuffle() |> hd

  pending_user =
    User.registration_changeset(%User{}, %{
      email: String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org"),
      password: "very_secure_password",
      role: :member,
      state: :pending_approval,
      first_name: first_name,
      last_name: last_name,
      phone_number: "+1415900900#{n}",
      confirmed_at: DateTime.utc_now(),
      most_connected_country: countries |> Enum.shuffle() |> hd,
      family_members: fam_members,
      registration_form: %{
        membership_type: membership_type,
        membership_eligibility: ["citizen_of_scandinavia", "born_in_scandinavia"],
        occupation: "Plumber",
        birth_date: "1970-02-04",
        address: "Dance St 2",
        country: "USA",
        city: "Dance Town",
        region: "CA",
        postal_code: "9470#{n}",
        place_of_birth: "Sweden",
        citizenship: "USA",
        most_connected_nordic_country: "Sweden",
        link_to_scandinavia: "Love it!",
        lived_in_scandinavia: "For a few seconds.",
        spoken_languages: "English and German",
        hear_about_the_club: "On internet",
        agreed_to_bylaws: "true",
        agreed_to_bylaws_at: DateTime.utc_now(),
        started: DateTime.utc_now(),
        completed: DateTime.utc_now(),
        browser_timezone: "America/Los_Angeles"
      }
    })

  Repo.insert!(
    pending_user,
    on_conflict: :nothing
  )
end)

Enum.each(0..n_rejected_users, fn n ->
  first_name = first_names |> Enum.shuffle() |> hd
  last_name = last_names |> Enum.shuffle() |> hd

  rejected_user =
    User.registration_changeset(%User{}, %{
      email: String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org"),
      password: "very_secure_password",
      role: :member,
      state: :rejected,
      first_name: first_name,
      last_name: last_name,
      phone_number: "+1415900900#{n}",
      most_connected_country: countries |> Enum.shuffle() |> hd,
      registration_form: %{
        membership_type: "family",
        membership_eligibiltiy: [],
        occupation: "Plumber",
        birth_date: "1900-01-01",
        address: "Dance St 2",
        country: "USA",
        city: "Dance Town",
        region: "CA",
        postal_code: "94700",
        place_of_birth: "USA",
        citizenship: "USA",
        most_connected_nordic_country: "Iceland",
        link_to_scandinavia: "Love it!",
        lived_in_scandinavia: "For a few seconds.",
        spoken_languages: "English",
        hear_about_the_club: "On internet",
        agreed_to_bylaws: "true",
        agreed_to_bylaws_at: DateTime.utc_now(),
        started: DateTime.utc_now(),
        completed: DateTime.utc_now(),
        browser_timezone: "America/Los_Angeles",
        reviewed_at: DateTime.utc_now(),
        review_outcome: "rejected",
        reviewed_by_user_id: admin_user.id
      }
    })

  Repo.insert!(
    rejected_user,
    on_conflict: :nothing
  )
end)

Enum.each(0..n_deleted_users, fn n ->
  first_name = first_names |> Enum.shuffle() |> hd
  last_name = last_names |> Enum.shuffle() |> hd

  deleted_user =
    User.registration_changeset(%User{}, %{
      email: String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org"),
      password: "very_secure_password",
      role: :member,
      state: :deleted,
      first_name: first_name,
      last_name: last_name,
      phone_number: "+1415900900#{n}",
      most_connected_country: countries |> Enum.shuffle() |> hd,
      registration_form: %{
        membership_type: "family",
        membership_eligibility: [],
        occupation: "Plumber",
        birth_date: "1970-04-02",
        address: "Dance St 2",
        country: "USA",
        city: "Dance Town",
        region: "CA",
        postal_code: "94700",
        place_of_birth: "USA",
        citizenship: "USA",
        most_connected_nordic_country: "Iceland",
        link_to_scandinavia: "Love it!",
        lived_in_scandinavia: "For a few seconds.",
        spoken_languages: "English",
        hear_about_the_club: "On internet",
        agreed_to_bylaws: "true",
        agreed_to_bylaws_at: DateTime.utc_now(),
        started: DateTime.utc_now(),
        completed: DateTime.utc_now(),
        browser_timezone: "America/Los_Angeles",
        reviewed_at: DateTime.utc_now(),
        review_outcome: "approved",
        reviewed_by_user_id: admin_user.id
      }
    })

  Repo.insert!(
    deleted_user,
    on_conflict: :nothing
  )
end)
