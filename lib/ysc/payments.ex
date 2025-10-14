defmodule Ysc.Payments do
  @moduledoc """
  The Payments context for managing payment methods and related operations.
  """

  import Ecto.Query, warn: false
  alias Ysc.Repo
  alias Ysc.Payments.PaymentMethod

  @doc """
  Returns the list of payment methods for a user.
  """
  def list_payment_methods(user) do
    Repo.all(from pm in PaymentMethod, where: pm.user_id == ^user.id)
  end

  @doc """
  Gets a single payment method by provider and provider_id.
  """
  def get_payment_method_by_provider(provider, provider_id) do
    Repo.get_by(PaymentMethod, provider: provider, provider_id: provider_id)
  end

  @doc """
  Gets a single payment method by id.
  """
  def get_payment_method!(id), do: Repo.get!(PaymentMethod, id)

  @doc """
  Creates a payment method with deduplication logic.
  """
  def insert_payment_method(attrs \\ %{}) do
    %PaymentMethod{}
    |> PaymentMethod.changeset(attrs)
    |> Repo.insert()
    |> handle_duplicate_payment_method()
  end

  @doc """
  Updates a payment method.
  """
  def update_payment_method(%PaymentMethod{} = payment_method, attrs) do
    payment_method
    |> PaymentMethod.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a payment method.
  """
  def delete_payment_method(%PaymentMethod{} = payment_method) do
    Repo.delete(payment_method)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking payment method changes.
  """
  def change_payment_method(%PaymentMethod{} = payment_method, attrs \\ %{}) do
    PaymentMethod.changeset(payment_method, attrs)
  end

  @doc """
  Handles deduplication of payment methods by provider and provider_id.
  If a payment method with the same provider and provider_id already exists,
  it updates the existing one instead of creating a duplicate.
  """
  def deduplicate_payment_methods(user) do
    payment_methods = list_payment_methods(user)

    # Group by provider and provider_id to find duplicates
    grouped = Enum.group_by(payment_methods, &{&1.provider, &1.provider_id})

    # Keep only the most recent payment method for each provider/provider_id combination
    {to_keep, to_delete} =
      grouped
      |> Enum.reduce({[], []}, fn {_key, methods}, {keep, delete} ->
        if length(methods) > 1 do
          # Sort by inserted_at desc and keep the first (most recent)
          sorted_methods = Enum.sort_by(methods, & &1.inserted_at, {:desc, DateTime})
          [most_recent | duplicates] = sorted_methods
          {[most_recent | keep], duplicates ++ delete}
        else
          {methods ++ keep, delete}
        end
      end)

    # Delete duplicate payment methods
    Enum.each(to_delete, &delete_payment_method/1)

    {:ok, to_keep}
  end

  @doc """
  Sets a payment method as the default for a user if they don't already have one.
  """
  def set_default_payment_method_if_none(user, payment_method) do
    # Check if user already has a default payment method
    existing_default =
      from(pm in PaymentMethod, where: pm.user_id == ^user.id and pm.is_default == true)
      |> Repo.one()

    if is_nil(existing_default) do
      set_default_payment_method(user, payment_method)
    else
      {:ok, user}
    end
  end

  @doc """
  Sets a payment method as the default for a user.
  This will unset any existing default payment method and set the new one.
  """
  def set_default_payment_method(user, payment_method) do
    Repo.transaction(fn ->
      # First, unset any existing default payment methods for this user
      from(pm in PaymentMethod, where: pm.user_id == ^user.id and pm.is_default == true)
      |> Repo.update_all(set: [is_default: false])

      # Then set the new payment method as default
      payment_method
      |> PaymentMethod.changeset(%{is_default: true})
      |> Repo.update!()
    end)
  end

  @doc """
  Creates or updates a payment method from Stripe data.
  """
  def upsert_payment_method_from_stripe(user, stripe_payment_method) do
    attrs = %{
      provider: :stripe,
      provider_id: stripe_payment_method.id,
      provider_customer_id: stripe_payment_method.customer,
      type: map_stripe_type_to_payment_method_type(stripe_payment_method.type),
      provider_type: stripe_payment_method.type,
      last_four: get_last_four(stripe_payment_method),
      display_brand: get_display_brand(stripe_payment_method),
      exp_month: stripe_payment_method.card && stripe_payment_method.card.exp_month,
      exp_year: stripe_payment_method.card && stripe_payment_method.card.exp_year,
      account_type:
        stripe_payment_method.us_bank_account &&
          stripe_payment_method.us_bank_account.account_type,
      routing_number:
        stripe_payment_method.us_bank_account &&
          stripe_payment_method.us_bank_account.routing_number,
      bank_name:
        stripe_payment_method.us_bank_account && stripe_payment_method.us_bank_account.bank_name,
      user_id: user.id,
      payload: stripe_payment_method_to_map(stripe_payment_method)
    }

    case get_payment_method_by_provider(:stripe, stripe_payment_method.id) do
      nil -> insert_payment_method(attrs)
      existing_payment_method -> update_payment_method(existing_payment_method, attrs)
    end
  end

  # Private functions

  defp handle_duplicate_payment_method(
         {:error, %Ecto.Changeset{errors: [provider_id: {"has already been taken", _}]}}
       ) do
    {:error, :duplicate_payment_method}
  end

  defp handle_duplicate_payment_method(result), do: result

  defp map_stripe_type_to_payment_method_type("card"), do: :card
  defp map_stripe_type_to_payment_method_type("us_bank_account"), do: :bank_account
  defp map_stripe_type_to_payment_method_type(type), do: String.to_atom(type)

  defp get_last_four(%{card: %{last4: last4}}), do: last4
  defp get_last_four(%{us_bank_account: %{last4: last4}}), do: last4
  defp get_last_four(_), do: nil

  defp get_display_brand(%{card: %{brand: brand}}), do: brand
  defp get_display_brand(%{us_bank_account: %{bank_name: bank_name}}), do: bank_name
  defp get_display_brand(_), do: nil

  defp stripe_payment_method_to_map(stripe_payment_method) do
    # Convert Stripe struct to map for storage
    Map.from_struct(stripe_payment_method)
    |> Enum.map(fn {key, value} -> {key, convert_to_map(value)} end)
    |> Enum.into(%{})
  end

  defp convert_to_map(%{__struct__: _module} = struct) do
    Map.from_struct(struct)
    |> Enum.map(fn {key, value} -> {key, convert_to_map(value)} end)
    |> Enum.into(%{})
  end

  defp convert_to_map(%{} = map) do
    Enum.map(map, fn {key, value} -> {key, convert_to_map(value)} end)
    |> Enum.into(%{})
  end

  defp convert_to_map(list) when is_list(list) do
    Enum.map(list, &convert_to_map/1)
  end

  defp convert_to_map(value), do: value
end
