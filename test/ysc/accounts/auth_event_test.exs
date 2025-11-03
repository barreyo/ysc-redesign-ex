defmodule Ysc.Accounts.AuthEventTest do
  use Ysc.DataCase, async: true

  alias Ysc.Accounts.{AuthEvent, AuthService}

  describe "AuthEvent" do
    test "creates a successful login event" do
      user = user_fixture()

      # Mock connection data
      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [{"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}]
      }

      {:ok, auth_event} = AuthService.log_login_success(user, conn)

      assert auth_event.user_id == user.id
      assert auth_event.event_type == "login_success"
      assert auth_event.success == true
      assert auth_event.email_attempted == user.email
      assert auth_event.ip_address == "127.0.0.1"
      assert auth_event.user_agent == "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
    end

    test "creates a failed login event" do
      email = "test@example.com"

      # Mock connection data
      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [{"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}]
      }

      {:ok, auth_event} = AuthService.log_login_failure(email, conn)

      assert auth_event.user_id == nil
      assert auth_event.event_type == "login_failure"
      assert auth_event.success == false
      assert auth_event.email_attempted == email
      assert auth_event.failure_reason == "invalid_credentials"
      assert auth_event.ip_address == "127.0.0.1"
    end

    test "creates a logout event" do
      user = user_fixture()

      # Mock connection data
      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [{"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}]
      }

      {:ok, auth_event} = AuthService.log_logout(user, conn)

      assert auth_event.user_id == user.id
      assert auth_event.event_type == "logout"
      assert auth_event.success == true
      assert auth_event.email_attempted == user.email
    end

    test "parses user agent correctly" do
      user_agent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

      parsed = AuthEvent.parse_user_agent(user_agent)

      assert parsed.device_type == "desktop"
      assert parsed.browser == "Chrome"
      assert parsed.operating_system == "macOS"
    end

    test "calculates risk score correctly" do
      # Low risk
      low_risk_attrs = %{threat_indicators: []}
      assert AuthEvent.calculate_risk_score(low_risk_attrs) == 0

      # Medium risk
      medium_risk_attrs = %{threat_indicators: ["new_device", "unusual_time"]}
      risk_score = AuthEvent.calculate_risk_score(medium_risk_attrs)
      assert risk_score > 0
      assert risk_score < 100

      # High risk
      high_risk_attrs = %{
        threat_indicators: ["new_device", "unusual_location", "rapid_attempts", "suspicious_ip"]
      }

      risk_score = AuthEvent.calculate_risk_score(high_risk_attrs)
      assert risk_score > 50
    end

    test "identifies suspicious activity" do
      # Not suspicious
      normal_attrs = %{threat_indicators: []}
      refute AuthEvent.suspicious?(normal_attrs)

      # Suspicious
      suspicious_attrs = %{
        threat_indicators: ["new_device", "unusual_location", "rapid_attempts", "suspicious_ip"]
      }

      assert AuthEvent.suspicious?(suspicious_attrs)
    end

    test "handles invalid UTF-8 in user agent" do
      # Test with invalid UTF-8 byte sequence
      invalid_utf8_user_agent = "Mozilla/5.0 \xa1\xa2\xa3"

      parsed = AuthEvent.parse_user_agent(invalid_utf8_user_agent)

      # Should still work and return valid data
      assert parsed.device_type in ["desktop", "mobile", "tablet", "unknown"]
      assert parsed.browser in ["Chrome", "Firefox", "Safari", "Edge", "Opera", "Unknown", nil]
    end

    test "sanitizes UTF-8 strings in AuthService" do
      # Test the sanitize_utf8 function
      invalid_string = "Test\xa1\xa2\xa3String"
      sanitized = Ysc.Accounts.AuthService.sanitize_utf8(invalid_string)

      # Should replace invalid characters with ?
      assert sanitized == "Test???String"

      # Should handle nil
      assert Ysc.Accounts.AuthService.sanitize_utf8(nil) == nil

      # Should handle valid UTF-8
      valid_string = "Valid UTF-8 string"
      assert Ysc.Accounts.AuthService.sanitize_utf8(valid_string) == valid_string

      # Should handle null bytes (PostgreSQL doesn't allow them)
      null_byte_string = "Test\x00String"
      sanitized_null = Ysc.Accounts.AuthService.sanitize_utf8(null_byte_string)
      assert sanitized_null == "TestString"
    end

    test "gets last successful login datetime" do
      user = user_fixture()

      # Initially no login events
      assert AuthService.get_last_successful_login_datetime(user) == nil
      assert AuthService.get_last_successful_login_event(user) == nil

      # Mock connection data
      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [{"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}]
      }

      # Log a successful login
      {:ok, auth_event} = AuthService.log_login_success(user, conn)

      # Should now return the login datetime
      last_login_datetime = AuthService.get_last_successful_login_datetime(user)
      assert last_login_datetime != nil
      assert DateTime.compare(last_login_datetime, auth_event.inserted_at) == :eq

      # Should also return the full event
      last_login_event = AuthService.get_last_successful_login_event(user)
      assert last_login_event != nil
      assert last_login_event.id == auth_event.id
    end

    test "gets last login session information" do
      user = user_fixture()

      # Mock connection data
      conn = %Plug.Conn{
        remote_ip: {127, 0, 0, 1},
        req_headers: [{"user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}]
      }

      # Initially no session data
      assert AuthService.get_last_login_session_datetime(user) == nil
      assert AuthService.get_last_login_session_event(user) == nil
      assert AuthService.get_last_session_timeframe(user) == nil

      # Log a successful login
      {:ok, login_event} = AuthService.log_login_success(user, conn)

      # Add a delay to ensure timestamps are different
      Process.sleep(1000)

      # Should return login time as last session activity
      last_session_datetime = AuthService.get_last_login_session_datetime(user)
      assert last_session_datetime != nil
      assert DateTime.compare(last_session_datetime, login_event.inserted_at) == :eq

      # Should return the login event as last session event
      last_session_event = AuthService.get_last_login_session_event(user)
      assert last_session_event != nil
      assert last_session_event.id == login_event.id

      # Should return session timeframe showing user is active
      session_timeframe = AuthService.get_last_session_timeframe(user)
      assert session_timeframe != nil
      assert session_timeframe.session_start == login_event.inserted_at
      assert session_timeframe.session_end == nil
      assert session_timeframe.is_active == true

      # Log a logout
      {:ok, logout_event} = AuthService.log_logout(user, conn)

      # Should now return logout time as last session activity
      last_session_datetime = AuthService.get_last_login_session_datetime(user)
      assert last_session_datetime != nil
      assert DateTime.compare(last_session_datetime, logout_event.inserted_at) == :eq

      # Should return the logout event as last session event
      last_session_event = AuthService.get_last_login_session_event(user)
      assert last_session_event != nil
      assert last_session_event.event_type == "logout"

      # Should return session timeframe showing user is not active
      session_timeframe = AuthService.get_last_session_timeframe(user)
      assert session_timeframe != nil
      assert session_timeframe.session_start == login_event.inserted_at
      assert session_timeframe.session_end == logout_event.inserted_at
      assert session_timeframe.is_active == false
    end
  end

  defp user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "test@example.com",
        password: "hello world!",
        first_name: "Test",
        last_name: "User",
        phone_number: "+14155551234",
        state: :active,
        role: :member
      })
      |> Ysc.Accounts.register_user()

    user
  end
end
