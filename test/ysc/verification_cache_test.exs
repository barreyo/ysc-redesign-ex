defmodule Ysc.VerificationCacheTest do
  use ExUnit.Case, async: false

  alias Ysc.VerificationCache

  setup do
    # Check if already started, if so, use existing, otherwise start
    case Process.whereis(VerificationCache) do
      nil -> start_supervised!(VerificationCache)
      _pid -> :ok
    end

    :ok
  end

  describe "store_code/4" do
    test "stores a verification code" do
      user_id = "user123"
      code_type = :email_verification
      code = "123456"

      assert :ok = VerificationCache.store_code(user_id, code_type, code, 600)
    end
  end

  describe "get_code/2" do
    test "retrieves stored code" do
      user_id = "user456"
      code_type = :sms_verification
      code = "654321"

      :ok = VerificationCache.store_code(user_id, code_type, code, 600)
      assert {:ok, ^code} = VerificationCache.get_code(user_id, code_type)
    end

    test "returns not_found for non-existent code" do
      assert {:error, :not_found} = VerificationCache.get_code("nonexistent", :email_verification)
    end

    test "returns expired for expired code" do
      user_id = "user789"
      code_type = :email_verification
      code = "999999"

      # Store with very short expiration
      :ok = VerificationCache.store_code(user_id, code_type, code, 1)
      # Wait for expiration
      Process.sleep(1100)
      assert {:error, :expired} = VerificationCache.get_code(user_id, code_type)
    end
  end

  describe "verify_code/3" do
    test "verifies correct code and removes it" do
      user_id = "user101"
      code_type = :sms_verification
      code = "111111"

      :ok = VerificationCache.store_code(user_id, code_type, code, 600)
      assert {:ok, :verified} = VerificationCache.verify_code(user_id, code_type, code)
      # Code should be removed after verification
      assert {:error, :not_found} = VerificationCache.get_code(user_id, code_type)
    end

    test "returns invalid_code for wrong code" do
      user_id = "user202"
      code_type = :email_verification
      code = "222222"

      :ok = VerificationCache.store_code(user_id, code_type, code, 600)
      assert {:error, :invalid_code} = VerificationCache.verify_code(user_id, code_type, "wrong")
      # Code should still exist
      assert {:ok, ^code} = VerificationCache.get_code(user_id, code_type)
    end

    test "returns expired for expired code" do
      user_id = "user303"
      code_type = :email_verification
      code = "333333"

      :ok = VerificationCache.store_code(user_id, code_type, code, 1)
      Process.sleep(1100)
      assert {:error, :expired} = VerificationCache.verify_code(user_id, code_type, code)
    end
  end

  describe "remove_code/2" do
    test "removes code from cache" do
      user_id = "user404"
      code_type = :sms_verification
      code = "444444"

      :ok = VerificationCache.store_code(user_id, code_type, code, 600)
      assert :ok = VerificationCache.remove_code(user_id, code_type)
      assert {:error, :not_found} = VerificationCache.get_code(user_id, code_type)
    end
  end

  describe "cleanup_expired/0" do
    test "cleans up expired codes" do
      user_id1 = "user505"
      user_id2 = "user606"
      code_type = :email_verification

      # Store one code with short expiration
      :ok = VerificationCache.store_code(user_id1, code_type, "555555", 1)
      # Store another with long expiration
      :ok = VerificationCache.store_code(user_id2, code_type, "666666", 600)

      Process.sleep(1100)

      # Cleanup should remove expired code
      assert :ok = VerificationCache.cleanup_expired()
      assert {:error, :not_found} = VerificationCache.get_code(user_id1, code_type)
      assert {:ok, "666666"} = VerificationCache.get_code(user_id2, code_type)
    end
  end
end
