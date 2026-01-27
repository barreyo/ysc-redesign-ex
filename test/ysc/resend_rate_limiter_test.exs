defmodule Ysc.ResendRateLimiterTest do
  use ExUnit.Case, async: true

  alias Ysc.ResendRateLimiter

  setup do
    # Clear cache before each test
    :ok
  end

  describe "resend_allowed?/3" do
    test "returns allowed when no rate limit is set" do
      assert {:ok, :allowed} = ResendRateLimiter.resend_allowed?("user123", :email, 60)
    end

    test "returns rate limited after recording resend" do
      identifier = "user456"
      type = :sms

      assert {:ok, :allowed} = ResendRateLimiter.resend_allowed?(identifier, type, 60)
      :ok = ResendRateLimiter.record_resend(identifier, type, 60)

      assert {:error, :rate_limited, _remaining} =
               ResendRateLimiter.resend_allowed?(identifier, type, 60)
    end
  end

  describe "record_resend/3" do
    test "records resend operation" do
      identifier = "user789"
      type = :email

      assert :ok = ResendRateLimiter.record_resend(identifier, type, 60)
      assert {:error, :rate_limited, _} = ResendRateLimiter.resend_allowed?(identifier, type, 60)
    end
  end

  describe "check_and_record_resend/3" do
    test "allows and records when not rate limited" do
      identifier = "user101"
      type = :email

      assert {:ok, :allowed} = ResendRateLimiter.check_and_record_resend(identifier, type, 60)
      assert {:error, :rate_limited, _} = ResendRateLimiter.resend_allowed?(identifier, type, 60)
    end

    test "returns rate limited when already rate limited" do
      identifier = "user202"
      type = :sms

      :ok = ResendRateLimiter.record_resend(identifier, type, 60)

      assert {:error, :rate_limited, _remaining} =
               ResendRateLimiter.check_and_record_resend(identifier, type, 60)
    end
  end

  describe "remaining_seconds/3" do
    test "returns 0 when not rate limited" do
      assert 0 == ResendRateLimiter.remaining_seconds("user303", :email, 60)
    end

    test "returns positive value when rate limited" do
      identifier = "user404"
      type = :sms

      :ok = ResendRateLimiter.record_resend(identifier, type, 60)
      remaining = ResendRateLimiter.remaining_seconds(identifier, type, 60)
      assert remaining > 0
    end
  end

  describe "disabled_until/1" do
    test "returns future datetime" do
      disabled_until = ResendRateLimiter.disabled_until(60)
      assert %DateTime{} = disabled_until
      assert DateTime.compare(disabled_until, DateTime.utc_now()) == :gt
    end
  end

  describe "resend_available?/2" do
    test "returns true when no disabled_until in assigns" do
      assigns = %{}
      assert ResendRateLimiter.resend_available?(assigns, :email) == true
      assert ResendRateLimiter.resend_available?(assigns, :sms) == true
    end

    test "returns false when disabled_until is in future" do
      disabled_until = DateTime.add(DateTime.utc_now(), 30, :second)
      assigns = %{email_resend_disabled_until: disabled_until}
      assert ResendRateLimiter.resend_available?(assigns, :email) == false
    end

    test "returns true when disabled_until is in past" do
      disabled_until = DateTime.add(DateTime.utc_now(), -10, :second)
      assigns = %{email_resend_disabled_until: disabled_until}
      assert ResendRateLimiter.resend_available?(assigns, :email) == true
    end
  end

  describe "resend_seconds_remaining/2" do
    test "returns 0 when no disabled_until" do
      assigns = %{}
      assert ResendRateLimiter.resend_seconds_remaining(assigns, :email) == 0
    end

    test "returns remaining seconds when disabled_until is set" do
      disabled_until = DateTime.add(DateTime.utc_now(), 45, :second)
      assigns = %{sms_resend_disabled_until: disabled_until}
      remaining = ResendRateLimiter.resend_seconds_remaining(assigns, :sms)
      assert remaining > 0
      assert remaining <= 45
    end
  end
end
