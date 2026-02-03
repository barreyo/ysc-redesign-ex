defmodule Ysc.Env do
  @moduledoc """
  Helpers for runtime environment checks.

  Provides clean, consistent functions to check the current runtime environment
  without relying on Mix (which is not available in production releases).

  ## Examples

      if Ysc.Env.test?() do
        # Test-specific behavior
      end

      unless Ysc.Env.prod?() do
        # Development/test behavior
      end

      if Ysc.Env.sandbox?() do
        # Sandbox-specific behavior
      end
  """

  @doc """
  Returns the current environment as a string.

  Falls back to "prod" if not configured.
  """
  @spec current() :: String.t()
  def current do
    Application.get_env(:ysc, :environment, "prod")
  end

  @doc """
  Returns true if running in test environment.
  """
  @spec test?() :: boolean()
  def test? do
    current() == "test"
  end

  @doc """
  Returns true if running in development environment.
  """
  @spec dev?() :: boolean()
  def dev? do
    current() == "dev"
  end

  @doc """
  Returns true if running in production environment.
  """
  @spec prod?() :: boolean()
  def prod? do
    current() == "prod"
  end

  @doc """
  Returns true if running in sandbox environment.
  """
  @spec sandbox?() :: boolean()
  def sandbox? do
    current() == "sandbox"
  end

  @doc """
  Returns true if running in a non-production environment (dev, test, or sandbox).

  Useful for enabling debug features or relaxing validation in lower environments.
  """
  @spec non_prod?() :: boolean()
  def non_prod? do
    current() in ["dev", "test", "sandbox"]
  end
end
