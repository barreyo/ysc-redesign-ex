defmodule YscWeb.Workers.MailpoetSubscriberTest do
  @moduledoc """
  Tests for MailpoetSubscriber worker.
  """
  use Ysc.DataCase, async: false

  alias YscWeb.Workers.MailpoetSubscriber

  describe "perform/1" do
    test "handles missing API configuration gracefully" do
      # Ensure Mailpoet API is not configured
      original_config = Application.get_env(:ysc, :mailpoet)
      Application.put_env(:ysc, :mailpoet, nil)

      job = %Oban.Job{
        id: 1,
        args: %{"email" => "test@example.com", "list_id" => 1},
        worker: "YscWeb.Workers.MailpoetSubscriber",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = MailpoetSubscriber.perform(job)
      assert result == :ok

      # Restore original config
      if original_config do
        Application.put_env(:ysc, :mailpoet, original_config)
      end
    end

    test "handles invalid email gracefully" do
      # Configure Mailpoet to return invalid email error
      Application.put_env(:ysc, :mailpoet, api_url: "http://test.com", api_key: "test_key")

      job = %Oban.Job{
        id: 1,
        args: %{"email" => "invalid", "list_id" => 1},
        worker: "YscWeb.Workers.MailpoetSubscriber",
        queue: "mailers",
        state: "available",
        attempt: 1
      }

      result = MailpoetSubscriber.perform(job)
      assert {:error, "Invalid email address"} = result
    end
  end
end
