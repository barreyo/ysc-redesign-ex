defmodule Ysc.Quickbooks.ClientTest do
  @moduledoc """
  Tests for Quickbooks.Client module.

  Since Client performs actual HTTP requests, most functionality is tested
  via integration tests with mocks (see sync_test.exs).

  This module provides basic module validation.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Quickbooks.Client

  describe "module" do
    test "is loaded and compiled" do
      assert Code.ensure_loaded?(Client)
    end
  end
end
