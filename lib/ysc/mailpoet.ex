defmodule Ysc.Mailpoet do
  @moduledoc """
  The Mailpoet context for managing email subscriptions.

  This module provides functions to subscribe and unsubscribe emails
  to/from Mailpoet lists via the Mailpoet REST API.
  """

  require Logger

  @doc """
  Subscribes an email address to a Mailpoet list.

  ## Examples

      iex> subscribe_email("user@example.com", list_id: 1)
      {:ok, %{status: "subscribed"}}

      iex> subscribe_email("invalid-email")
      {:error, :invalid_email}

  """
  @spec subscribe_email(String.t(), keyword()) ::
          {:ok, map()} | {:error, atom() | String.t()}
  def subscribe_email(email, opts \\ []) do
    with :ok <- validate_email(email),
         {:ok, api_url} <- get_api_url(),
         {:ok, api_key} <- get_api_key(),
         list_id <- Keyword.get(opts, :list_id, get_default_list_id()) do
      subscribe_to_mailpoet(api_url, api_key, email, list_id)
    end
  end

  @doc """
  Unsubscribes an email address from a Mailpoet list.

  ## Examples

      iex> unsubscribe_email("user@example.com")
      {:ok, %{status: "unsubscribed"}}

  """
  @spec unsubscribe_email(String.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  def unsubscribe_email(email) do
    with :ok <- validate_email(email),
         {:ok, api_url} <- get_api_url(),
         {:ok, api_key} <- get_api_key() do
      unsubscribe_from_mailpoet(api_url, api_key, email)
    end
  end

  @doc """
  Gets the subscription status of an email address.

  ## Examples

      iex> get_subscription_status("user@example.com")
      {:ok, %{status: "subscribed"}}

  """
  @spec get_subscription_status(String.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  def get_subscription_status(email) do
    with :ok <- validate_email(email),
         {:ok, api_url} <- get_api_url(),
         {:ok, api_key} <- get_api_key() do
      check_subscription_status(api_url, api_key, email)
    end
  end

  # Private functions

  defp validate_email(email) when is_binary(email) do
    case Regex.run(~r/^[^\s]+@[^\s]+\.[^\s]+$/, email) do
      nil -> {:error, :invalid_email}
      _ -> :ok
    end
  end

  defp validate_email(_), do: {:error, :invalid_email}

  defp get_api_url do
    case Application.get_env(:ysc, :mailpoet)[:api_url] do
      nil -> {:error, :mailpoet_api_url_not_configured}
      url -> {:ok, url}
    end
  end

  defp get_api_key do
    case Application.get_env(:ysc, :mailpoet)[:api_key] do
      nil -> {:error, :mailpoet_api_key_not_configured}
      key -> {:ok, key}
    end
  end

  defp get_default_list_id do
    Application.get_env(:ysc, :mailpoet)[:default_list_id]
  end

  defp subscribe_to_mailpoet(api_url, api_key, email, list_id) do
    url = "#{api_url}/subscribers"
    headers = build_headers(api_key)
    body = build_subscribe_body(email, list_id)

    Logger.info("Subscribing email to Mailpoet",
      email: email,
      list_id: list_id,
      url: url
    )

    request = Finch.build(:post, url, headers, Jason.encode!(body))

    case Finch.request(request, Ysc.Finch) do
      {:ok, %{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, data} ->
            Logger.info("Successfully subscribed email to Mailpoet",
              email: email,
              list_id: list_id
            )

            {:ok, data}

          {:error, error} ->
            Logger.error("Failed to parse Mailpoet response",
              email: email,
              error: inspect(error)
            )

            {:error, :invalid_response}
        end

      {:ok, %{status: status, body: response_body}} ->
        Logger.error("Mailpoet API returned error status",
          email: email,
          status: status,
          response: response_body
        )

        {:error, "Mailpoet API error: #{status}"}

      {:error, error} ->
        Logger.error("Failed to subscribe email to Mailpoet",
          email: email,
          error: inspect(error)
        )

        {:error, :request_failed}
    end
  end

  defp unsubscribe_from_mailpoet(api_url, api_key, email) do
    # First, get the subscriber ID
    case get_subscriber_id(api_url, api_key, email) do
      {:ok, subscriber_id} ->
        url = "#{api_url}/subscribers/#{subscriber_id}"
        headers = build_headers(api_key)
        body = %{status: "unsubscribed"}

        Logger.info("Unsubscribing email from Mailpoet",
          email: email,
          subscriber_id: subscriber_id
        )

        request = Finch.build(:post, url, headers, Jason.encode!(body))

        case Finch.request(request, Ysc.Finch) do
          {:ok, %{status: 200, body: response_body}} ->
            case Jason.decode(response_body) do
              {:ok, data} ->
                Logger.info("Successfully unsubscribed email from Mailpoet",
                  email: email
                )

                {:ok, data}

              {:error, error} ->
                Logger.error("Failed to parse Mailpoet response",
                  email: email,
                  error: inspect(error)
                )

                {:error, :invalid_response}
            end

          {:ok, %{status: status, body: response_body}} ->
            Logger.error("Mailpoet API returned error status",
              email: email,
              status: status,
              response: response_body
            )

            {:error, "Mailpoet API error: #{status}"}

          {:error, error} ->
            Logger.error("Failed to unsubscribe email from Mailpoet",
              email: email,
              error: inspect(error)
            )

            {:error, :request_failed}
        end

      {:error, :subscriber_not_found} ->
        Logger.info("Subscriber not found in Mailpoet, already unsubscribed",
          email: email
        )

        {:ok, %{status: "unsubscribed", message: "Subscriber not found"}}

      error ->
        error
    end
  end

  defp check_subscription_status(api_url, api_key, email) do
    case get_subscriber_id(api_url, api_key, email) do
      {:ok, subscriber_id} ->
        url = "#{api_url}/subscribers/#{subscriber_id}"
        headers = build_headers(api_key)

        request = Finch.build(:get, url, headers)

        case Finch.request(request, Ysc.Finch) do
          {:ok, %{status: 200, body: response_body}} ->
            case Jason.decode(response_body) do
              {:ok, data} ->
                {:ok, data}

              {:error, error} ->
                Logger.error("Failed to parse Mailpoet response",
                  email: email,
                  error: inspect(error)
                )

                {:error, :invalid_response}
            end

          {:ok, %{status: status}} ->
            Logger.error("Mailpoet API returned error status",
              email: email,
              status: status
            )

            {:error, "Mailpoet API error: #{status}"}

          {:error, error} ->
            Logger.error("Failed to check subscription status",
              email: email,
              error: inspect(error)
            )

            {:error, :request_failed}
        end

      {:error, :subscriber_not_found} ->
        {:ok, %{status: "not_subscribed"}}

      error ->
        error
    end
  end

  defp get_subscriber_id(api_url, api_key, email) do
    url = "#{api_url}/subscribers"
    headers = build_headers(api_key)
    params = URI.encode_query(%{email: email})
    full_url = "#{url}?#{params}"

    request = Finch.build(:get, full_url, headers)

    case Finch.request(request, Ysc.Finch) do
      {:ok, %{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, data} ->
            case data do
              %{"data" => [%{"id" => id} | _]} -> {:ok, id}
              %{"data" => []} -> {:error, :subscriber_not_found}
              _ -> {:error, :invalid_response}
            end

          {:error, error} ->
            Logger.error("Failed to parse Mailpoet response",
              email: email,
              error: inspect(error)
            )

            {:error, :invalid_response}
        end

      {:ok, %{status: status}} ->
        Logger.error("Mailpoet API returned error status",
          email: email,
          status: status
        )

        {:error, "Mailpoet API error: #{status}"}

      {:error, error} ->
        Logger.error("Failed to get subscriber ID",
          email: email,
          error: inspect(error)
        )

        {:error, :request_failed}
    end
  end

  defp build_headers(api_key) do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Bearer #{api_key}"}
    ]
  end

  defp build_subscribe_body(email, list_id) when is_integer(list_id) do
    %{
      email: email,
      status: "subscribed",
      lists: [list_id]
    }
  end

  defp build_subscribe_body(email, _list_id) do
    %{
      email: email,
      status: "subscribed"
    }
  end
end
