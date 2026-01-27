defmodule Ysc.MailpoetTest do
  use ExUnit.Case, async: true

  alias Ysc.Mailpoet

  setup do
    # Configure Mailpoet for tests
    Application.put_env(:ysc, :mailpoet,
      api_url: "https://test.mailpoet.com/wp-json/mailpoet/v1",
      api_key: "test_api_key",
      default_list_id: 1
    )

    on_exit(fn ->
      Application.delete_env(:ysc, :mailpoet)
    end)

    :ok
  end

  describe "subscribe_email/2" do
    test "validates email format" do
      assert {:error, :invalid_email} = Mailpoet.subscribe_email("invalid-email")
      assert {:error, :invalid_email} = Mailpoet.subscribe_email("")
      assert {:error, :invalid_email} = Mailpoet.subscribe_email(nil)
    end

    test "returns error when api_url not configured" do
      Application.delete_env(:ysc, :mailpoet)

      assert {:error, :mailpoet_api_url_not_configured} =
               Mailpoet.subscribe_email("test@example.com")
    end

    test "returns error when api_key not configured" do
      Application.put_env(:ysc, :mailpoet, api_url: "https://test.com", api_key: nil)

      assert {:error, :mailpoet_api_key_not_configured} =
               Mailpoet.subscribe_email("test@example.com")
    end
  end

  describe "unsubscribe_email/1" do
    test "validates email format" do
      assert {:error, :invalid_email} = Mailpoet.unsubscribe_email("invalid-email")
      assert {:error, :invalid_email} = Mailpoet.unsubscribe_email("")
    end

    test "returns error when api_url not configured" do
      Application.delete_env(:ysc, :mailpoet)

      assert {:error, :mailpoet_api_url_not_configured} =
               Mailpoet.unsubscribe_email("test@example.com")
    end

    test "returns error when api_key not configured" do
      Application.put_env(:ysc, :mailpoet, api_url: "https://test.com", api_key: nil)

      assert {:error, :mailpoet_api_key_not_configured} =
               Mailpoet.unsubscribe_email("test@example.com")
    end
  end

  describe "get_subscription_status/1" do
    test "validates email format" do
      assert {:error, :invalid_email} = Mailpoet.get_subscription_status("invalid-email")
      assert {:error, :invalid_email} = Mailpoet.get_subscription_status("")
    end

    test "returns error when api_url not configured" do
      Application.delete_env(:ysc, :mailpoet)

      assert {:error, :mailpoet_api_url_not_configured} =
               Mailpoet.get_subscription_status("test@example.com")
    end

    test "returns error when api_key not configured" do
      Application.put_env(:ysc, :mailpoet, api_url: "https://test.com", api_key: nil)

      assert {:error, :mailpoet_api_key_not_configured} =
               Mailpoet.get_subscription_status("test@example.com")
    end
  end
end
