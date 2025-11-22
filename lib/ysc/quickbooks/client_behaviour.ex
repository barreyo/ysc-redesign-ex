defmodule Ysc.Quickbooks.ClientBehaviour do
  @moduledoc """
  Behaviour for QuickBooks API client to enable testing with mocks.
  """

  @doc """
  Creates a SalesReceipt in QuickBooks.
  """
  @callback create_sales_receipt(map()) :: {:ok, map()} | {:error, atom() | String.t()}

  @doc """
  Creates a Deposit in QuickBooks.
  """
  @callback create_deposit(map()) :: {:ok, map()} | {:error, atom() | String.t()}

  @doc """
  Creates a Customer in QuickBooks.
  """
  @callback create_customer(map()) :: {:ok, map()} | {:error, atom() | String.t()}
end
