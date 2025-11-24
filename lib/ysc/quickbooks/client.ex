defmodule Ysc.Quickbooks.Client do
  @moduledoc """
  QuickBooks Online API client for accounting operations.

  This client handles OAuth2 authentication and provides functions to create
  SalesReceipts (for purchases and refunds) and Deposits (for Stripe payouts).

  Implements `Ysc.Quickbooks.ClientBehaviour` for testability.
  """
  @behaviour Ysc.Quickbooks.ClientBehaviour

  require Logger

  # Default base URL (production)
  @default_api_base_url "https://quickbooks.api.intuit.com/v3"
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
  - `QUICKBOOKS_COMPANY_ID` - Your QuickBooks company ID
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
         {:ok, company_id} <- get_company_id() do
      url = build_url(company_id, "salesreceipt")
      headers = build_headers(access_token)
      body = build_sales_receipt_body(params)

      Logger.info("Creating QuickBooks SalesReceipt",
        company_id: company_id,
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
         {:ok, company_id} <- get_company_id() do
      url = build_url(company_id, "deposit")
      headers = build_headers(access_token)
      body = build_deposit_body(params)

      Logger.info("Creating QuickBooks Deposit",
        company_id: company_id,
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
         {:ok, company_id} <- get_company_id() do
      url = build_url(company_id, "customer")
      headers = build_headers(access_token)
      body = build_customer_body(params)

      Logger.info("Creating QuickBooks Customer",
        company_id: company_id,
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

  @doc """
  Gets or creates a QuickBooks Item by name.

  First tries to find an existing item by name, and if not found, creates a new one.
  Returns the item ID.

  ## Parameters

    - `name` - The name of the item to find or create
    - `opts` - Optional parameters:
      - `:type` - Item type (default: "Service"). Can be "Service", "Inventory", "NonInventory"
      - `:income_account_ref` - Income account reference (optional)
      - `:expense_account_ref` - Expense account reference (optional)

  ## Examples

      Client.get_or_create_item("Event Tickets")
      Client.get_or_create_item("Donations", type: "Service")
  """
  @spec get_or_create_item(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, atom() | String.t()}
  def get_or_create_item(name, opts \\ []) do
    Logger.debug("[QB Client] get_or_create_item: Getting or creating item",
      name: name,
      opts: opts
    )

    # First check cache
    cache_key = "qb_item_#{name}"
    cached_id = get_cached_item_id(cache_key)

    if cached_id do
      Logger.debug("[QB Client] get_or_create_item: Found in cache",
        name: name,
        item_id: cached_id
      )

      {:ok, cached_id}
    else
      # Try to find existing item
      case query_item_by_name(name) do
        {:ok, item_id} ->
          cache_item_id(cache_key, item_id)
          {:ok, item_id}

        {:error, :not_found} ->
          # Create new item
          Logger.info("[QB Client] get_or_create_item: Item not found, creating new item",
            name: name
          )

          case create_item(name, opts) do
            {:ok, item_id} ->
              cache_item_id(cache_key, item_id)
              {:ok, item_id}

            error ->
              error
          end

        error ->
          error
      end
    end
  end

  defp query_item_by_name(name) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      # Query for item by name
      query =
        "SELECT Id, Name FROM Item WHERE Name = '#{escape_query_string(name)}' AND Active = true"

      url = build_query_url(company_id, query)
      headers = build_headers(access_token)

      Logger.debug("[QB Client] query_item_by_name: Querying for item",
        name: name,
        query: query
      )

      request = Finch.build(:get, url, headers)

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, %{"QueryResponse" => %{"Item" => items}}}
            when is_list(items) and length(items) > 0 ->
              item = List.first(items)
              item_id = Map.get(item, "Id")

              Logger.debug("[QB Client] query_item_by_name: Found item",
                name: name,
                item_id: item_id
              )

              {:ok, item_id}

            {:ok, %{"QueryResponse" => %{"Item" => item}}} when is_map(item) ->
              item_id = Map.get(item, "Id")

              Logger.debug("[QB Client] query_item_by_name: Found item",
                name: name,
                item_id: item_id
              )

              {:ok, item_id}

            {:ok, %{"QueryResponse" => _}} ->
              Logger.debug("[QB Client] query_item_by_name: Item not found",
                name: name
              )

              {:error, :not_found}

            {:ok, data} ->
              Logger.error("[QB Client] query_item_by_name: Unexpected response format",
                name: name,
                data: inspect(data)
              )

              {:error, :invalid_response}

            {:error, error} ->
              Logger.error("[QB Client] query_item_by_name: Failed to parse response",
                name: name,
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning(
            "[QB Client] query_item_by_name: Authentication failed, attempting token refresh"
          )

          case refresh_access_token() do
            {:ok, new_access_token} ->
              headers = build_headers(new_access_token)
              request = Finch.build(:get, url, headers)

              case Finch.request(request, Ysc.Finch) do
                {:ok, %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, %{"QueryResponse" => %{"Item" => items}}}
                    when is_list(items) and length(items) > 0 ->
                      item_id = List.first(items) |> Map.get("Id")
                      {:ok, item_id}

                    {:ok, %{"QueryResponse" => %{"Item" => item}}} when is_map(item) ->
                      item_id = Map.get(item, "Id")
                      {:ok, item_id}

                    _ ->
                      {:error, :not_found}
                  end

                _ ->
                  {:error, :query_failed}
              end

            error ->
              error
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          Logger.error("[QB Client] query_item_by_name: Query failed",
            name: name,
            status: status,
            response: response_body
          )

          {:error, :query_failed}

        {:error, error} ->
          Logger.error("[QB Client] query_item_by_name: Request failed",
            name: name,
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  defp create_item(name, opts) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      item_type = Keyword.get(opts, :type, "Service")
      url = build_url(company_id, "item")
      headers = build_headers(access_token)

      body = build_item_body(name, item_type, opts)

      Logger.debug("[QB Client] create_item: Creating item",
        name: name,
        type: item_type
      )

      request = Finch.build(:post, url, headers, Jason.encode!(body))

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, data} ->
              item = get_response_entity(data, "Item")
              item_id = Map.get(item, "Id")

              Logger.info("[QB Client] create_item: Successfully created item",
                name: name,
                item_id: item_id
              )

              {:ok, item_id}

            {:error, error} ->
              Logger.error("[QB Client] create_item: Failed to parse response",
                name: name,
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning(
            "[QB Client] create_item: Authentication failed, attempting token refresh"
          )

          case refresh_access_token() do
            {:ok, new_access_token} ->
              headers = build_headers(new_access_token)
              request = Finch.build(:post, url, headers, Jason.encode!(body))

              case Finch.request(request, Ysc.Finch) do
                {:ok, %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, data} ->
                      item = get_response_entity(data, "Item")
                      item_id = Map.get(item, "Id")
                      {:ok, item_id}

                    error ->
                      {:error, :invalid_response}
                  end

                _ ->
                  {:error, :create_failed}
              end

            error ->
              error
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error("[QB Client] create_item: Failed to create item",
            name: name,
            status: status,
            error: error
          )

          {:error, error}

        {:error, error} ->
          Logger.error("[QB Client] create_item: Request failed",
            name: name,
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    end
  end

  defp build_item_body(name, type, opts) do
    base = %{
      "Name" => name,
      "Type" => type,
      "Active" => true
    }

    base
    |> maybe_put("IncomeAccountRef", opts[:income_account_ref])
    |> maybe_put("ExpenseAccountRef", opts[:expense_account_ref])
  end

  defp build_query_url(company_id, query) do
    base_url = get_api_base_url()
    base_url = String.trim_trailing(base_url, "/")

    base_url =
      if String.ends_with?(base_url, "/company"),
        do: String.replace_suffix(base_url, "/company", ""),
        else: base_url

    encoded_query = URI.encode(query)

    "#{base_url}/company/#{company_id}/query?query=#{encoded_query}&minorversion=#{@minor_version}"
  end

  defp escape_query_string(str) do
    str
    |> String.replace("'", "''")
    |> String.replace("\\", "\\\\")
  end

  defp get_cached_item_id(cache_key) do
    # Use application environment as a simple cache
    Application.get_env(:ysc, :quickbooks_item_cache, %{})[cache_key]
  end

  defp cache_item_id(cache_key, item_id) do
    current_cache = Application.get_env(:ysc, :quickbooks_item_cache, %{})
    updated_cache = Map.put(current_cache, cache_key, item_id)
    Application.put_env(:ysc, :quickbooks_item_cache, updated_cache)
  end

  # Private functions

  defp build_url(company_id, endpoint) do
    base_url = get_api_base_url()
    # Ensure base_url doesn't have trailing slash and doesn't already include /company
    base_url = String.trim_trailing(base_url, "/")

    base_url =
      if String.ends_with?(base_url, "/company"),
        do: String.replace_suffix(base_url, "/company", ""),
        else: base_url

    "#{base_url}/company/#{company_id}/#{endpoint}?minorversion=#{@minor_version}"
  end

  defp get_api_base_url do
    case Application.get_env(:ysc, :quickbooks)[:url] do
      nil -> @default_api_base_url
      url when is_binary(url) -> url
      _ -> @default_api_base_url
    end
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
    # Note: PrivateNote is not supported for SalesReceipt in QuickBooks Online API
    # Use Memo instead if you need to store additional notes
    |> maybe_put("Memo", params[:memo] || params[:private_note])
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
            "Qty" => detail.quantity,
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

  @doc """
  Queries for a QuickBooks Account by name.

  Returns {:ok, account_id} if found, {:error, :not_found} otherwise.
  """
  @spec query_account_by_name(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def query_account_by_name(name) do
    with {:ok, access_token} <- get_access_token(),
         {:ok, company_id} <- get_company_id() do
      # Query for account by name
      query =
        "SELECT Id, Name FROM Account WHERE Name = '#{escape_query_string(name)}' AND Active = true"

      url = build_query_url(company_id, query)
      headers = build_headers(access_token)

      Logger.debug("[QB Client] query_account_by_name: Querying for account",
        name: name,
        query: query
      )

      request = Finch.build(:get, url, headers)

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, %{"QueryResponse" => %{"Account" => accounts}}}
            when is_list(accounts) and length(accounts) > 0 ->
              account = List.first(accounts)
              account_id = Map.get(account, "Id")

              Logger.debug("[QB Client] query_account_by_name: Found account",
                name: name,
                account_id: account_id
              )

              {:ok, account_id}

            {:ok, %{"QueryResponse" => %{"Account" => account}}} when is_map(account) ->
              account_id = Map.get(account, "Id")

              Logger.debug("[QB Client] query_account_by_name: Found account",
                name: name,
                account_id: account_id
              )

              {:ok, account_id}

            {:ok, %{"QueryResponse" => _}} ->
              Logger.debug("[QB Client] query_account_by_name: Account not found",
                name: name
              )

              {:error, :not_found}

            {:ok, data} ->
              Logger.error("[QB Client] query_account_by_name: Unexpected response format",
                name: name,
                data: inspect(data)
              )

              {:error, :invalid_response}

            {:error, error} ->
              Logger.error("[QB Client] query_account_by_name: Failed to parse response",
                name: name,
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: 401, body: _response_body}} ->
          Logger.warning(
            "[QB Client] query_account_by_name: Authentication failed, attempting token refresh"
          )

          case refresh_access_token() do
            {:ok, new_access_token} ->
              headers = build_headers(new_access_token)
              request = Finch.build(:get, url, headers)

              case Finch.request(request, Ysc.Finch) do
                {:ok, %Finch.Response{status: status, body: retry_response_body}}
                when status in 200..299 ->
                  case Jason.decode(retry_response_body) do
                    {:ok, %{"QueryResponse" => %{"Account" => accounts}}}
                    when is_list(accounts) and length(accounts) > 0 ->
                      account = List.first(accounts)
                      account_id = Map.get(account, "Id")
                      {:ok, account_id}

                    {:ok, %{"QueryResponse" => %{"Account" => account}}} when is_map(account) ->
                      account_id = Map.get(account, "Id")
                      {:ok, account_id}

                    _ ->
                      {:error, :not_found}
                  end

                _ ->
                  {:error, :not_found}
              end

            error ->
              error
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          error = parse_error_response(response_body)

          Logger.error("[QB Client] query_account_by_name: Failed to query account",
            name: name,
            status: status,
            error: error
          )

          {:error, error}

        {:error, error} ->
          Logger.error("[QB Client] query_account_by_name: Request failed",
            name: name,
            error: inspect(error)
          )

          {:error, :request_failed}
      end
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
    qb_config = Application.get_env(:ysc, :quickbooks, [])

    Logger.debug("[QB Client] get_access_token: Checking configuration",
      has_access_token: !is_nil(qb_config[:access_token]),
      has_refresh_token: !is_nil(qb_config[:refresh_token]),
      has_client_id: !is_nil(qb_config[:client_id]),
      has_client_secret: !is_nil(qb_config[:client_secret]),
      has_company_id: !is_nil(qb_config[:company_id])
    )

    case qb_config[:access_token] do
      nil ->
        Logger.debug(
          "[QB Client] get_access_token: Access token not configured, attempting to refresh"
        )

        # Try to refresh the token if we have a refresh token
        case refresh_access_token() do
          {:ok, new_token} ->
            Logger.debug("[QB Client] get_access_token: Successfully refreshed access token")
            {:ok, new_token}

          error ->
            Logger.error("[QB Client] get_access_token: Failed to refresh token",
              error: inspect(error)
            )

            {:error, :quickbooks_access_token_not_configured}
        end

      token ->
        Logger.debug("[QB Client] get_access_token: Using configured access token")
        {:ok, token}
    end
  end

  defp get_company_id do
    case Application.get_env(:ysc, :quickbooks)[:company_id] do
      nil -> {:error, :quickbooks_company_id_not_configured}
      company_id -> {:ok, company_id}
    end
  end

  defp refresh_access_token do
    Logger.debug("[QB Client] refresh_access_token: Starting token refresh")

    with {:ok, client_id} <- get_client_id(),
         {:ok, client_secret} <- get_client_secret(),
         {:ok, refresh_token} <- get_refresh_token() do
      Logger.debug("[QB Client] refresh_access_token: Got credentials, making refresh request",
        url: @token_url,
        has_client_id: !is_nil(client_id),
        has_client_secret: !is_nil(client_secret),
        has_refresh_token: !is_nil(refresh_token)
      )

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

      # Create Basic Auth header: Base64(ClientID:ClientSecret)
      auth_header = Base.encode64("#{client_id}:#{client_secret}")
      headers = [{"Authorization", "Basic #{auth_header}"} | headers]

      Logger.debug("[QB Client] refresh_access_token: Request details",
        url: url,
        grant_type: "refresh_token",
        has_auth_header: !is_nil(auth_header),
        body_params: %{grant_type: "refresh_token", refresh_token: "[REDACTED]"}
      )

      request = Finch.build(:post, url, headers, body)

      case Finch.request(request, Ysc.Finch) do
        {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
          Logger.debug("[QB Client] refresh_access_token: Got successful response",
            status: status
          )

          case Jason.decode(response_body) do
            {:ok,
             %{"access_token" => access_token, "refresh_token" => new_refresh_token} =
                 response_data} ->
              # Extract expiration info if available
              expires_in = Map.get(response_data, "expires_in")
              token_type = Map.get(response_data, "token_type", "Bearer")

              # Update application config (in production, you'd want to persist this)
              update_token_config(access_token, new_refresh_token)

              Logger.warning(
                "[QB Client] ⚠️  IMPORTANT: New refresh token received. Update your .env file with: QUICKBOOKS_REFRESH_TOKEN=\"#{new_refresh_token}\""
              )

              Logger.info("[QB Client] Successfully refreshed QuickBooks access token",
                access_token_length: String.length(access_token),
                refresh_token_length: String.length(new_refresh_token),
                access_token_preview: String.slice(access_token, 0, 20) <> "...",
                refresh_token_preview: String.slice(new_refresh_token, 0, 20) <> "...",
                expires_in: expires_in,
                token_type: token_type
              )

              {:ok, access_token}

            {:ok, data} ->
              Logger.error("[QB Client] refresh_access_token: Unexpected token refresh response",
                data: inspect(data),
                response_keys: if(is_map(data), do: Map.keys(data), else: :not_a_map)
              )

              {:error, :invalid_token_response}

            {:error, error} ->
              Logger.error(
                "[QB Client] refresh_access_token: Failed to parse token refresh response",
                error: inspect(error)
              )

              {:error, :invalid_response}
          end

        {:ok, %Finch.Response{status: status, body: response_body}} ->
          Logger.error("[QB Client] refresh_access_token: Token refresh failed",
            status: status,
            response: response_body
          )

          {:error, :token_refresh_failed}

        {:error, error} ->
          Logger.error("[QB Client] refresh_access_token: Request failed during token refresh",
            error: inspect(error)
          )

          {:error, :request_failed}
      end
    else
      error ->
        Logger.error("[QB Client] refresh_access_token: Failed to get required credentials",
          error: inspect(error)
        )

        error
    end
  end

  defp get_client_id do
    case Application.get_env(:ysc, :quickbooks)[:client_id] do
      nil ->
        Logger.error("[QB Client] get_client_id: QUICKBOOKS_CLIENT_ID not configured")
        {:error, :quickbooks_client_id_not_configured}

      client_id ->
        Logger.debug("[QB Client] get_client_id: Client ID found",
          has_client_id: !is_nil(client_id)
        )

        {:ok, client_id}
    end
  end

  defp get_client_secret do
    case Application.get_env(:ysc, :quickbooks)[:client_secret] do
      nil ->
        Logger.error("[QB Client] get_client_secret: QUICKBOOKS_CLIENT_SECRET not configured")
        {:error, :quickbooks_client_secret_not_configured}

      client_secret ->
        Logger.debug("[QB Client] get_client_secret: Client secret found",
          has_client_secret: !is_nil(client_secret)
        )

        {:ok, client_secret}
    end
  end

  defp get_refresh_token do
    case Application.get_env(:ysc, :quickbooks)[:refresh_token] do
      nil ->
        Logger.error("[QB Client] get_refresh_token: QUICKBOOKS_REFRESH_TOKEN not configured")
        {:error, :quickbooks_refresh_token_not_configured}

      token ->
        Logger.debug("[QB Client] get_refresh_token: Refresh token found",
          has_refresh_token: !is_nil(token)
        )

        {:ok, token}
    end
  end

  defp update_token_config(access_token, refresh_token) do
    # IMPORTANT: When a new refresh token is received, it MUST be saved to persistent storage.
    # The old refresh token may become invalid. For now, we update the in-memory config,
    # but you MUST update your .env file or database with the new refresh_token.
    #
    # In production, consider:
    # 1. Storing tokens in a database table
    # 2. Using a secrets management service (AWS Secrets Manager, etc.)
    # 3. At minimum, updating the .env file with the new refresh_token

    current_config = Application.get_env(:ysc, :quickbooks, [])

    updated_config =
      Keyword.merge(current_config,
        access_token: access_token,
        refresh_token: refresh_token
      )

    Application.put_env(:ysc, :quickbooks, updated_config)

    Logger.debug("[QB Client] update_token_config: Updated in-memory config",
      has_access_token: !is_nil(access_token),
      has_refresh_token: !is_nil(refresh_token)
    )
  end
end
