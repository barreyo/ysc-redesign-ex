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

admin_user =
  User.registration_changeset(%User{}, %{
    email: "admin@ysc.org",
    password: "very_secure_password",
    role: :admin,
    state: :active,
    first_name: "Admin",
    last_name: "User",
    phone_number: "+14159009009",
    confirmed_at: DateTime.utc_now()
  })

Repo.insert!(
  admin_user,
  on_conflict: :nothing
)

regular_user =
  User.registration_changeset(%User{}, %{
    email: "regular@ysc.org",
    password: "very_secure_password",
    role: :member,
    state: :active,
    first_name: "Regular",
    last_name: "Member",
    phone_number: "+14159009009",
    confirmed_at: DateTime.utc_now()
  })

Repo.insert!(
  regular_user,
  on_conflict: :nothing
)

pending_approval_user =
  User.registration_changeset(%User{}, %{
    email: "pending@ysc.org",
    password: "very_secure_password",
    role: :member,
    state: :pending_approval,
    first_name: "Pending",
    last_name: "Member",
    phone_number: "+14159009009"
  })

Repo.insert!(
  pending_approval_user,
  on_conflict: :nothing
)

rejected_user =
  User.registration_changeset(%User{}, %{
    email: "rejected@ysc.org",
    password: "very_secure_password",
    role: :member,
    state: :rejected,
    first_name: "Rejected",
    last_name: "Member",
    phone_number: "+14159009009"
  })

Repo.insert!(
  rejected_user,
  on_conflict: :nothing
)
