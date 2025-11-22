defmodule Ysc.Quickbooks.Client do
  @moduledoc """
  QuickBooks Online API client for accounting operations.

  This client handles OAuth2 authentication and provides functions to create
  SalesReceipts (for purchases and refunds) and Deposits (for Stripe payouts).

  Implements `Ysc.Quickbooks.ClientBehaviour` for testability.
  """
  @behaviour Ysc.Quickbooks.ClientBehaviour

  require Logger

  @api_base_url "https://quickbooks.api.intuit.com/v3/company"
  @token_url "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer"
  # Latest minor version as of 2024
  @minor_version "65"

  @doc """
  Creates a SalesReceipt in QuickBooks.

  SalesReceipts are used to record sales transactions where payment is received immediately.
  This can be used for both purchases and refunds (use negative amounts for refunds).

  ## Configuration

  The following environment variables are required:
  - `QUICKBOOKS_CLIENT_ID` - Your QuickBooks app client ID
  - `QUICKBOOKS_CLIENT_SECRET` - Your QuickBooks app client secret
  - `QUICKBOOKS_REALM_ID` - Your QuickBooks company/realm ID
  - `QUICKBOOKS_ACCESS_TOKEN` - OAuth2 access token (can be refreshed)
  - `QUICKBOOKS_REFRESH_TOKEN` - OAuth2 refresh token

  ## Usage

      alias Ysc.Quickbooks.Client

      # Create a sales receipt for a purchase
      Client.create_sales_receipt(%{
        customer_ref: %{value: "123"},
        line: [
          %{
            amount: 100.00,
            detail_type: "SalesItemLineDetail",
            sales_item_line_detail: %{
              item_ref: %{value: "456"},
              quantity: 1,
              unit_price: 100.00
            }
          }
        ],
        total_amt: 100.00
      })

      # Create a deposit for a Stripe payout
      Client.create_deposit(%{
        deposit_to_account_ref: %{value: "789"},
        line: [
          %{
            amount: 500.00,
            detail_type: "DepositLineDetail",
            deposit_line_detail: %{
              entity_ref: %{value: "101112", type: "Account"}
            }
          }
        ],
        total_amt: 500.00
      })

  ## Parameters

    - `params` - Map containing SalesReceipt data:
      - `customer_ref` (required) - Map with `value` key containing customer ID
      - `line` (required) - List of line items
      - `total_amt` (required) - Total amount
      - `payment_method_ref` (optional) - Payment method reference
      - `deposit_to_account_ref` (optional) - Account to deposit to
      - `doc_number` (optional) - Document number
      - `txn_date` (optional) - Transaction date (ISO 8601 format)
      - `private_note` (optional) - Private note
      - `memo` (optional) - Public memo

  ## Examples

      # Purchase
      Client.create_sales_receipt(%{
        customer_ref: %{value: "123"},
        line: [
          %{
            amount: 100.00,
            detail_type: "SalesItemLineDetail",
            sales_item_line_detail: %{
              item_ref: %{value: "456"},
              quantity: 1,
              unit_price: 100.00
            }
          }
        ],
        total_amt: 100.00,
        payment_method_ref: %{value: "789"},
        txn_date: "2024-01-15"
      })

      # Refund (negative amount)
      Client.create_sales_receipt(%{
        customer_ref: %{value: "123"},
        line: [
          %{
            amount: -50.00,
            detail_type: "SalesItemLineDetail",
            sales_item_line_detail: %{
              item_ref: %{value: "456"},
              quantity: 1,
              unit_price: -50.00
            }
          }
        ],
        total_amt: -50.00,
        payment_method_ref: %{value: "789"},
        txn_date: "2024-01-15"
      })

  """
  @spec create_sales_receipt(map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def create_sales_receipt(params) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, realm_id} <- get_realm_id() do
      url = build_url(realm_id, "salesreceipt")
      headers = build_headers(access_token)
      body = build_sales_receipt_body(params)

      Logger.info("Creating QuickBooks SalesReceipt",
        realm_id: realm_id,
        total_amt: Map.get(params, :total_amt)
      )

      request = Finch.build(:post, url, headers, Jason.encode!(body))

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, data} ->
              sales_receipt = get_response_entity(data, "SalesReceipt")

              Logger.info("Successfully created QuickBooks SalesReceipt",
                sales_receipt_id: Map.get(sales_receipt, "Id"),
                total_amt: Map.get(sales_receipt, "TotalAmt")
              )

              {:ok, sales_receipt}

            {:error, error} ->
              Logger.error("Failed to parse QuickBooks response",
                error: inspect(error),
                response: response_body
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning("QuickBooks authentication failed, attempting token refresh")
          # Try to refresh token and retry once
          case refresh_access_token() do
            {:ok, new_access_token} ->
              # Retry with new token
              headers = build_headers(new_access_token)
              request = Finch.build(:post, url, headers, Jason.encode!(body))

              case Finch.request(request, Ysc.Finch) do
                {:ok, %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, data} ->
                      sales_receipt = get_response_entity(data, "SalesReceipt")
                      {:ok, sales_receipt}

                    {:error, error} ->
                      Logger.error("Failed to parse QuickBooks response after retry",
                        error: inspect(error)
                      )

                      {:error, :invalid_response}
                  end

                {:ok, %Finch.Response{status: status, body: retry_response_body}} ->
                  error = parse_error_response(retry_response_body)

                  Logger.error("QuickBooks API error after token refresh",
                    status: status,
                    error: error
                  )

                  {:error, error}

                {:error, error} ->
                  Logger.error("Request failed after token refresh", error: inspect(error))
                  {:error, :request_failed}
              end

            error ->
              Logger.error("Failed to refresh QuickBooks access token", error: inspect(error))
              {:error, :authentication_failed}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error("QuickBooks API error",
            status: status,
            error: error,
            endpoint: "salesreceipt"
          )

          {:error, error}

        {:error, error} ->
          Logger.error("Failed to create QuickBooks SalesReceipt", error: inspect(error))
          {:error, :request_failed}
      end
    end
  end

  @doc """
  Creates a Deposit in QuickBooks.

  Deposits are used to record money deposited into a bank account.
  This is typically used for Stripe payouts.

  ## Parameters

    - `params` - Map containing Deposit data:
      - `deposit_to_account_ref` (required) - Map with `value` key containing bank account ID
      - `line` (required) - List of deposit line items
      - `total_amt` (required) - Total deposit amount
      - `txn_date` (optional) - Transaction date (ISO 8601 format)
      - `private_note` (optional) - Private note
      - `memo` (optional) - Public memo

  ## Examples

      # Stripe payout deposit
      Client.create_deposit(%{
        deposit_to_account_ref: %{value: "789"},
        line: [
          %{
            amount: 500.00,
            detail_type: "DepositLineDetail",
            deposit_line_detail: %{
              entity_ref: %{value: "101112", type: "Account"}
            }
          }
        ],
        total_amt: 500.00,
        txn_date: "2024-01-15",
        memo: "Stripe payout for period ending 2024-01-15"
      })

  """
  @spec create_deposit(map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def create_deposit(params) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, realm_id} <- get_realm_id() do
      url = build_url(realm_id, "deposit")
      headers = build_headers(access_token)
      body = build_deposit_body(params)

      Logger.info("Creating QuickBooks Deposit",
        realm_id: realm_id,
        total_amt: Map.get(params, :total_amt)
      )

      request = Finch.build(:post, url, headers, Jason.encode!(body))

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, data} ->
              deposit = get_response_entity(data, "Deposit")

              Logger.info("Successfully created QuickBooks Deposit",
                deposit_id: Map.get(deposit, "Id"),
                total_amt: Map.get(deposit, "TotalAmt")
              )

              {:ok, deposit}

            {:error, error} ->
              Logger.error("Failed to parse QuickBooks response",
                error: inspect(error),
                response: response_body
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning("QuickBooks authentication failed, attempting token refresh")
          # Try to refresh token and retry once
          case refresh_access_token() do
            {:ok, new_access_token} ->
              # Retry with new token
              headers = build_headers(new_access_token)
              request = Finch.build(:post, url, headers, Jason.encode!(body))

              case Finch.request(request, Ysc.Finch) do
                {:ok, %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, data} ->
                      deposit = get_response_entity(data, "Deposit")
                      {:ok, deposit}

                    {:error, error} ->
                      Logger.error("Failed to parse QuickBooks response after retry",
                        error: inspect(error)
                      )

                      {:error, :invalid_response}
                  end

                {:ok, %Finch.Response{status: status, body: retry_response_body}} ->
                  error = parse_error_response(retry_response_body)

                  Logger.error("QuickBooks API error after token refresh",
                    status: status,
                    error: error
                  )

                  {:error, error}

                {:error, error} ->
                  Logger.error("Request failed after token refresh", error: inspect(error))
                  {:error, :request_failed}
              end

            error ->
              Logger.error("Failed to refresh QuickBooks access token", error: inspect(error))
              {:error, :authentication_failed}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error("QuickBooks API error",
            status: status,
            error: error,
            endpoint: "deposit"
          )

          {:error, error}

        {:error, error} ->
          Logger.error("Failed to create QuickBooks Deposit", error: inspect(error))
          {:error, :request_failed}
      end
    end
  end

  @doc """
  Creates a Customer in QuickBooks.

  ## Parameters

    - `params` - Map containing Customer data:
      - `display_name` (required) - Customer display name
      - `email` (optional) - Primary email address
      - `phone` (optional) - Primary phone number
      - `company_name` (optional) - Company name
      - `given_name` (optional) - First name
      - `family_name` (optional) - Last name
      - `notes` (optional) - Notes about the customer
      - `bill_address` (optional) - Billing address map with keys: line1, city, country_sub_division_code, postal_code, country

  ## Examples

      Client.create_customer(%{
        display_name: "John Doe",
        email: "john@example.com",
        phone: "555-1234",
        given_name: "John",
        family_name: "Doe"
      })

  """
  @spec create_customer(map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def create_customer(params) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, realm_id} <- get_realm_id() do
      url = build_url(realm_id, "customer")
      headers = build_headers(access_token)
      body = build_customer_body(params)

      Logger.info("Creating QuickBooks Customer",
        realm_id: realm_id,
        display_name: params.display_name
      )

      request = Finch.build(:post, url, headers, Jason.encode!(body))

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, data} ->
              customer = get_response_entity(data, "Customer")

              Logger.info("Successfully created QuickBooks Customer",
                customer_id: Map.get(customer, "Id"),
                display_name: Map.get(customer, "DisplayName")
              )

              {:ok, customer}

            {:error, error} ->
              Logger.error("Failed to parse QuickBooks response",
                error: inspect(error),
                response: response_body
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning("QuickBooks authentication failed, attempting token refresh")
          # Try to refresh token and retry once
          case refresh_access_token() do
            {:ok, new_access_token} ->
              # Retry with new token
              headers = build_headers(new_access_token)
              request = Finch.build(:post, url, headers, Jason.encode!(body))

              case Finch.request(request, Ysc.Finch) do
                {:ok, %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, data} ->
                      customer = get_response_entity(data, "Customer")
                      {:ok, customer}

                    {:error, error} ->
                      Logger.error("Failed to parse QuickBooks response after retry",
                        error: inspect(error)
                      )

                      {:error, :invalid_response}
                  end

                {:ok, %Finch.Response{status: status, body: retry_response_body}} ->
                  error = parse_error_response(retry_response_body)

                  Logger.error("QuickBooks API error after token refresh",
                    status: status,
                    error: error
                  )

                  {:error, error}

                {:error, error} ->
                  Logger.error("Request failed after token refresh", error: inspect(error))
                  {:error, :request_failed}
              end

            error ->
              Logger.error("Failed to refresh QuickBooks access token", error: inspect(error))
              {:error, :authentication_failed}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error("QuickBooks API error",
            status: status,
            error: error,
            endpoint: "customer"
          )

          {:error, error}

        {:error, error} ->
          Logger.error("Failed to create QuickBooks Customer", error: inspect(error))
          {:error, :request_failed}
      end
    end
  end

  # Private functions

  defp build_url(realm_id, endpoint) do
    "#{@api_base_url}/#{realm_id}/#{endpoint}?minorversion=#{@minor_version}"
  end

  defp build_headers(access_token) do
    [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
  end

  defp build_sales_receipt_body(params) do
    %{
      "CustomerRef" => params.customer_ref,
      "Line" => Enum.map(params.line, &normalize_line_item/1),
      "TotalAmt" => params.total_amt
    }
    |> maybe_put("PaymentMethodRef", params[:payment_method_ref])
    |> maybe_put("DepositToAccountRef", params[:deposit_to_account_ref])
    |> maybe_put("DocNumber", params[:doc_number])
    |> maybe_put("TxnDate", params[:txn_date])
    |> maybe_put("PrivateNote", params[:private_note])
    |> maybe_put("Memo", params[:memo])
  end

  defp build_deposit_body(params) do
    %{
      "DepositToAccountRef" => params.deposit_to_account_ref,
      "Line" => Enum.map(params.line, &normalize_deposit_line_item/1),
      "TotalAmt" => params.total_amt
    }
    |> maybe_put("TxnDate", params[:txn_date])
    |> maybe_put("PrivateNote", params[:private_note])
    |> maybe_put("Memo", params[:memo])
  end

  defp build_customer_body(params) do
    %{"DisplayName" => params.display_name}
    |> maybe_put("GivenName", params[:given_name])
    |> maybe_put("FamilyName", params[:family_name])
    |> maybe_put("CompanyName", params[:company_name])
    |> maybe_put("PrimaryEmailAddr", params[:email] && %{"Address" => params.email})
    |> maybe_put("PrimaryPhone", params[:phone] && %{"FreeFormNumber" => params.phone})
    |> maybe_put("Notes", params[:notes])
    |> maybe_put("BillAddr", build_address(params[:bill_address]))
  end

  defp build_address(nil), do: nil

  defp build_address(addr) when is_map(addr) do
    %{}
    |> maybe_put("Line1", addr[:line1])
    |> maybe_put("City", addr[:city])
    |> maybe_put("CountrySubDivisionCode", addr[:country_sub_division_code])
    |> maybe_put("PostalCode", addr[:postal_code])
    |> maybe_put("Country", addr[:country] || "USA")
  end

  defp normalize_line_item(item) do
    base = %{
      "Amount" => item.amount,
      "DetailType" => item.detail_type
    }

    result =
      case item.detail_type do
        "SalesItemLineDetail" ->
          detail = item.sales_item_line_detail

          sales_detail = %{
            "ItemRef" => detail.item_ref,
            "Quantity" => detail.quantity,
            "UnitPrice" => detail.unit_price
          }

          sales_detail =
            if detail[:tax_code_ref],
              do: Map.put(sales_detail, "TaxCodeRef", detail.tax_code_ref),
              else: sales_detail

          sales_detail =
            if detail[:class_ref],
              do: Map.put(sales_detail, "ClassRef", detail.class_ref),
              else: sales_detail

          Map.put(base, "SalesItemLineDetail", sales_detail)

        "DiscountLineDetail" ->
          detail = item.discount_line_detail
          discount_detail = %{}

          discount_detail =
            if detail[:class_ref],
              do: Map.put(discount_detail, "ClassRef", detail.class_ref),
              else: discount_detail

          discount_detail =
            if detail[:percent_based],
              do: Map.put(discount_detail, "PercentBased", detail.percent_based),
              else: discount_detail

          discount_detail =
            if detail[:discount_percent],
              do: Map.put(discount_detail, "DiscountPercent", detail.discount_percent),
              else: discount_detail

          discount_detail =
            if detail[:discount_account_ref],
              do: Map.put(discount_detail, "DiscountAccountRef", detail.discount_account_ref),
              else: discount_detail

          Map.put(base, "DiscountLineDetail", discount_detail)

        _ ->
          base
      end

    if item[:description] do
      Map.put(result, "Description", item.description)
    else
      result
    end
  end

  defp normalize_deposit_line_item(item) do
    base = %{
      "Amount" => item.amount,
      "DetailType" => item.detail_type
    }

    case item.detail_type do
      "DepositLineDetail" ->
        detail = item.deposit_line_detail
        detail_map = %{}

        detail_map =
          if detail[:entity_ref] do
            Map.put(detail_map, "Entity", detail.entity_ref)
          else
            detail_map
          end

        detail_map =
          if detail[:account_ref] do
            Map.put(detail_map, "AccountRef", detail.account_ref)
          else
            detail_map
          end

        detail_map =
          if detail[:class_ref] do
            Map.put(detail_map, "ClassRef", detail.class_ref)
          else
            detail_map
          end

        detail_map =
          if detail[:payment_method_ref] do
            Map.put(detail_map, "PaymentMethodRef", detail.payment_method_ref)
          else
            detail_map
          end

        Map.put(base, "DepositLineDetail", detail_map)
        |> maybe_put("Description", item[:description])

      _ ->
        base
    end
  end

  defp maybe_put(map, key, value) when is_map(map) do
    if value != nil, do: Map.put(map, key, value), else: map
  end

  defp get_response_entity(data, entity_name) do
    case data do
      %{"QueryResponse" => %{^entity_name => [entity | _]}} -> entity
      %{"QueryResponse" => %{^entity_name => entity}} -> entity
      %{^entity_name => entity} -> entity
      _ -> data
    end
  end

  defp parse_error_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"Fault" => fault}} ->
        error = fault["Error"] || []
        first_error = List.first(error) || %{}
        message = first_error["Message"] || first_error["Detail"] || "Unknown error"
        code = first_error["code"] || "UNKNOWN"
        "#{code}: #{message}"

      {:ok, data} ->
        inspect(data)

      {:error, _} ->
        response_body
    end
  end

  defp get_access_token do
    case Application.get_env(:ysc, :quickbooks)[:access_token] do
      nil -> {:error, :quickbooks_access_token_not_configured}
      token -> {:ok, token}
    end
  end

  defp get_realm_id do
    case Application.get_env(:ysc, :quickbooks)[:realm_id] do
      nil -> {:error, :quickbooks_realm_id_not_configured}
      realm_id -> {:ok, realm_id}
    end
  end

  defp refresh_access_token do
    with {:ok, client_id} <- get_client_id(),
         {:ok, client_secret} <- get_client_secret(),
         {:ok, refresh_token} <- get_refresh_token() do
      url = @token_url

      headers = [
        {"Content-Type", "application/x-www-form-urlencoded"},
        {"Accept", "application/json"}
      ]

      body =
        URI.encode_query(%{
          grant_type: "refresh_token",
          refresh_token: refresh_token
        })

      auth_header = Base.encode64("#{client_id}:#{client_secret}")
      headers = [{"Authorization", "Basic #{auth_header}"} | headers]

      request = Finch.build(:post, url, headers, body)

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, %{"access_token" => access_token, "refresh_token" => new_refresh_token}} ->
              # Update application config (in production, you'd want to persist this)
              update_token_config(access_token, new_refresh_token)
              Logger.info("Successfully refreshed QuickBooks access token")
              {:ok, access_token}

            {:ok, data} ->
              Logger.error("Unexpected token refresh response", data: inspect(data))
              {:error, :invalid_token_response}

            {:error, error} ->
              Logger.error("Failed to parse token refresh response", error: inspect(error))
              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          Logger.error("Token refresh failed",
            status: status,
            response: response_body
          )

          {:error, :token_refresh_failed}

        {:error, error} ->
          Logger.error("Request failed during token refresh", error: inspect(error))
          {:error, :request_failed}
      end
    end
  end

  defp get_client_id do
    case Application.get_env(:ysc, :quickbooks)[:client_id] do
      nil -> {:error, :quickbooks_client_id_not_configured}
      client_id -> {:ok, client_id}
    end
  end

  defp get_client_secret do
    case Application.get_env(:ysc, :quickbooks)[:client_secret] do
      nil -> {:error, :quickbooks_client_secret_not_configured}
      client_secret -> {:ok, client_secret}
    end
  end

  defp get_refresh_token do
    case Application.get_env(:ysc, :quickbooks)[:refresh_token] do
      nil -> {:error, :quickbooks_refresh_token_not_configured}
      token -> {:ok, token}
    end
  end

  defp update_token_config(access_token, refresh_token) do
    # In production, you should persist these tokens to a database or secure storage
    # For now, we'll update the application environment
    current_config = Application.get_env(:ysc, :quickbooks, [])

    updated_config =
      Keyword.merge(current_config, access_token: access_token, refresh_token: refresh_token)

    Application.put_env(:ysc, :quickbooks, updated_config)
  end
end
