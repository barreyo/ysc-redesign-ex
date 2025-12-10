# Test dev mode phone verification
alias Ysc.{Accounts, Repo}

IO.puts("=== Testing Dev Mode Phone Verification ===")

# Create a test user
user_attrs = %{
  email: "dev-phone-test-#{System.unique_integer()}@example.com",
  first_name: "Dev",
  last_name: "Phone",
  password: "password123456",
  phone_number: "+14155551234",
  state: "pending_approval",
  role: "member"
}

{:ok, user} = Accounts.register_user(user_attrs)
IO.puts("✅ Created user for dev mode testing")

# Test that "000000" works in dev mode without any code being stored
IO.puts("\nTesting '000000' code in dev mode:")

case Accounts.verify_phone_verification_code(user, "000000") do
  {:ok, :verified} ->
    IO.puts("✅ Dev mode '000000' code accepted without stored code")

  {:error, reason} ->
    IO.puts("❌ Dev mode '000000' code rejected: #{reason}")
end

# Test that normal codes still work
IO.puts("\nTesting normal verification flow:")
code = Accounts.generate_and_store_phone_verification_code(user)
IO.puts("Generated code: #{code}")

case Accounts.verify_phone_verification_code(user, code) do
  {:ok, :verified} ->
    IO.puts("✅ Normal code verification works")

  {:error, reason} ->
    IO.puts("❌ Normal code verification failed: #{reason}")
end

# Test that "000000" still works even after normal verification
IO.puts("\nTesting '000000' after normal verification:")

case Accounts.verify_phone_verification_code(user, "000000") do
  {:ok, :verified} ->
    IO.puts("✅ Dev mode '000000' still works after normal verification")

  {:error, reason} ->
    IO.puts("❌ Dev mode '000000' failed after normal verification: #{reason}")
end

IO.puts("\n=== Dev Mode Phone Verification Test Complete ===")
