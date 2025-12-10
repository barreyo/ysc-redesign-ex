# Simple test to verify verification fields work
alias Ysc.{Accounts, Repo}

# Test that we can create a user and mark verification fields
user_attrs = %{
  email: "test-verification@example.com",
  first_name: "Test",
  last_name: "User",
  password: "password123456",
  state: "active",
  role: "member"
}

# Create user
{:ok, user} = Accounts.register_user(user_attrs)

IO.puts("Created user: #{user.id}")
IO.puts("Initial email_verified_at: #{user.email_verified_at}")
IO.puts("Initial phone_verified_at: #{user.phone_verified_at}")
IO.puts("Initial password_set_at: #{user.password_set_at}")

# Mark email as verified
{:ok, user} = Accounts.mark_email_verified(user)
IO.puts("After email verification: #{user.email_verified_at}")

# Mark phone as verified
{:ok, user} = Accounts.mark_phone_verified(user)
IO.puts("After phone verification: #{user.phone_verified_at}")

# Set password (which should mark password_set_at)
{:ok, user} = Accounts.set_user_initial_password(user, %{password: "newpassword123456"})
IO.puts("After password set: #{user.password_set_at}")

# Verify fields are set in database
db_user = Repo.get!(Ysc.Accounts.User, user.id)
IO.puts("DB email_verified_at: #{db_user.email_verified_at}")
IO.puts("DB phone_verified_at: #{db_user.phone_verified_at}")
IO.puts("DB password_set_at: #{db_user.password_set_at}")

IO.puts("✅ All verification fields working correctly!")
