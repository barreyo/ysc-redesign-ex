# Test the phone verification flow
alias Ysc.{Accounts, Repo}

IO.puts("=== Testing Phone Verification Flow ===")

# Create a test user
user_attrs = %{
  email: "phone-test@example.com",
  first_name: "Phone",
  last_name: "Test",
  password: "password123456",
  phone_number: "+14155551234",
  state: "pending_approval",
  role: "member"
}

{:ok, user} = Accounts.register_user(user_attrs)
IO.puts("✅ Created user with phone: #{user.phone_number}")

# Test generating and sending phone verification code
code = Accounts.generate_and_store_phone_verification_code(user)
IO.puts("✅ Generated phone verification code: #{code}")

# Check that code is stored
case Ysc.VerificationCache.get_code(user.id, :phone_verification) do
  {:ok, stored_code} ->
    IO.puts("✅ Code stored in cache: #{stored_code}")

  {:error, reason} ->
    IO.puts("❌ Code not stored: #{reason}")
end

# Test phone verification with the actual code
case Accounts.verify_phone_verification_code(user, code) do
  {:ok, :verified} ->
    IO.puts("✅ Phone verification successful with correct code")

  {:error, reason} ->
    IO.puts("❌ Phone verification failed: #{reason}")
end

# Test dev mode "000000" code
case Accounts.verify_phone_verification_code(user, "000000") do
  {:ok, :verified} ->
    IO.puts("✅ Dev mode '000000' code accepted")

  {:error, reason} ->
    IO.puts("❌ Dev mode '000000' code rejected: #{reason}")
end

# Check that verification code was removed after successful verification
case Ysc.VerificationCache.get_code(user.id, :phone_verification) do
  {:ok, _} ->
    IO.puts("❌ Code still in cache after verification")

  {:error, :not_found} ->
    IO.puts("✅ Code properly cleaned up from cache")
end

# Check database for phone_verified_at timestamp
db_user = Repo.get!(Ysc.Accounts.User, user.id)

if db_user.phone_verified_at do
  IO.puts("✅ Phone verification timestamp set: #{db_user.phone_verified_at}")
else
  IO.puts("❌ Phone verification timestamp not set")
end

IO.puts("\n=== Phone Verification Flow Test Complete ===")
