defmodule YscWeb.Workers.MailpoetSubscriber do
  @moduledoc """
  Oban worker for subscribing users to Mailpoet newsletter.

  Processes newsletter subscriptions asynchronously to avoid blocking
  user registration or other operations.
  """
  require Logger
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Ysc.Mailpoet

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email, "list_id" => list_id}})
      when is_integer(list_id) do
    Logger.info("MailpoetSubscriber: Starting subscription",
      email: email,
      list_id: list_id
    )

    case Mailpoet.subscribe_email(email, list_id: list_id) do
      {:ok, _response} ->
        Logger.info("MailpoetSubscriber: Successfully subscribed",
          email: email,
          list_id: list_id
        )

        :ok

      {:error, :invalid_email} ->
        Logger.warning("MailpoetSubscriber: Invalid email address",
          email: email
        )

        {:error, "Invalid email address"}

      {:error, :mailpoet_api_url_not_configured} ->
        Logger.debug("MailpoetSubscriber: API URL not configured, skipping",
          email: email
        )

        :ok

      {:error, :mailpoet_api_key_not_configured} ->
        Logger.debug("MailpoetSubscriber: API key not configured, skipping",
          email: email
        )

        :ok

      {:error, error} ->
        Logger.warning("MailpoetSubscriber: Failed to subscribe",
          email: email,
          error: inspect(error)
        )

        {:error, "Failed to subscribe: #{inspect(error)}"}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email, "action" => "subscribe"}}) do
    Logger.info("MailpoetSubscriber: Starting subscription",
      email: email
    )

    case Mailpoet.subscribe_email(email) do
      {:ok, _response} ->
        Logger.info("MailpoetSubscriber: Successfully subscribed",
          email: email
        )

        :ok

      {:error, :invalid_email} ->
        Logger.warning("MailpoetSubscriber: Invalid email address",
          email: email
        )

        {:error, "Invalid email address"}

      {:error, :mailpoet_api_url_not_configured} ->
        Logger.debug("MailpoetSubscriber: API URL not configured, skipping",
          email: email
        )

        :ok

      {:error, :mailpoet_api_key_not_configured} ->
        Logger.debug("MailpoetSubscriber: API key not configured, skipping",
          email: email
        )

        :ok

      {:error, error} ->
        Logger.warning("MailpoetSubscriber: Failed to subscribe",
          email: email,
          error: inspect(error)
        )

        {:error, "Failed to subscribe: #{inspect(error)}"}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email, "action" => "unsubscribe"}}) do
    Logger.info("MailpoetSubscriber: Starting unsubscribe",
      email: email
    )

    case Mailpoet.unsubscribe_email(email) do
      {:ok, _response} ->
        Logger.info("MailpoetSubscriber: Successfully unsubscribed",
          email: email
        )

        :ok

      {:error, :invalid_email} ->
        Logger.warning("MailpoetSubscriber: Invalid email address",
          email: email
        )

        {:error, "Invalid email address"}

      {:error, :mailpoet_api_url_not_configured} ->
        Logger.debug("MailpoetSubscriber: API URL not configured, skipping",
          email: email
        )

        :ok

      {:error, :mailpoet_api_key_not_configured} ->
        Logger.debug("MailpoetSubscriber: API key not configured, skipping",
          email: email
        )

        :ok

      {:error, error} ->
        Logger.warning("MailpoetSubscriber: Failed to unsubscribe",
          email: email,
          error: inspect(error)
        )

        {:error, "Failed to unsubscribe: #{inspect(error)}"}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email" => email}}) do
    # Legacy support: no action specified means subscribe
    Logger.info("MailpoetSubscriber: Starting subscription (legacy)",
      email: email
    )

    case Mailpoet.subscribe_email(email) do
      {:ok, _response} ->
        Logger.info("MailpoetSubscriber: Successfully subscribed",
          email: email
        )

        :ok

      {:error, :invalid_email} ->
        Logger.warning("MailpoetSubscriber: Invalid email address",
          email: email
        )

        {:error, "Invalid email address"}

      {:error, :mailpoet_api_url_not_configured} ->
        Logger.debug("MailpoetSubscriber: API URL not configured, skipping",
          email: email
        )

        :ok

      {:error, :mailpoet_api_key_not_configured} ->
        Logger.debug("MailpoetSubscriber: API key not configured, skipping",
          email: email
        )

        :ok

      {:error, error} ->
        Logger.warning("MailpoetSubscriber: Failed to subscribe",
          email: email,
          error: inspect(error)
        )

        {:error, "Failed to subscribe: #{inspect(error)}"}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.warning("MailpoetSubscriber: Invalid job args",
      args: args
    )

    {:error, "Invalid job args: email is required"}
  end
end
