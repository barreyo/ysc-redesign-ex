defmodule Ysc.PaymentsTest do
  use Ysc.DataCase, async: true

  alias Ysc.Payments
  alias Ysc.Payments.PaymentMethod
  import Ysc.AccountsFixtures

  describe "list_payment_methods/1" do
    test "returns payment methods for user" do
      user = user_fixture()
      _method1 = create_payment_method_fixture(%{user_id: user.id})
      _method2 = create_payment_method_fixture(%{user_id: user.id})

      methods = Payments.list_payment_methods(user)
      assert length(methods) >= 2
    end
  end

  describe "get_payment_method_by_provider/2" do
    test "returns payment method by provider and provider_id" do
      method = create_payment_method_fixture(%{provider: :stripe, provider_id: "pm_test123"})
      found = Payments.get_payment_method_by_provider(:stripe, "pm_test123")
      assert found.id == method.id
    end

    test "returns nil for non-existent payment method" do
      refute Payments.get_payment_method_by_provider(:stripe, "pm_nonexistent")
    end
  end

  describe "get_payment_method!/1" do
    test "returns payment method by id" do
      method = create_payment_method_fixture()
      found = Payments.get_payment_method!(method.id)
      assert found.id == method.id
    end

    test "raises for non-existent payment method" do
      assert_raise Ecto.NoResultsError, fn ->
        Payments.get_payment_method!(Ecto.ULID.generate())
      end
    end
  end

  describe "get_default_payment_method/1" do
    test "returns default payment method for user" do
      user = user_fixture()
      default = create_payment_method_fixture(%{user_id: user.id, is_default: true})
      _other = create_payment_method_fixture(%{user_id: user.id, is_default: false})

      found = Payments.get_default_payment_method(user)
      assert found.id == default.id
    end

    test "returns nil when no default payment method" do
      user = user_fixture()
      _method = create_payment_method_fixture(%{user_id: user.id, is_default: false})
      refute Payments.get_default_payment_method(user)
    end
  end

  describe "insert_payment_method/1" do
    test "creates a payment method" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        provider: :stripe,
        provider_id: "pm_new123",
        is_default: false
      }

      assert {:ok, method} = Payments.insert_payment_method(attrs)
      assert method.provider == :stripe
      assert method.provider_id == "pm_new123"
    end
  end

  describe "update_payment_method/2" do
    test "updates a payment method" do
      method = create_payment_method_fixture()
      update_attrs = %{is_default: true}

      assert {:ok, updated} = Payments.update_payment_method(method, update_attrs)
      assert updated.is_default == true
    end
  end

  describe "delete_payment_method/1" do
    test "deletes a payment method" do
      method = create_payment_method_fixture()
      assert {:ok, _} = Payments.delete_payment_method(method)

      assert_raise Ecto.NoResultsError, fn ->
        Payments.get_payment_method!(method.id)
      end
    end

    test "sets new default when deleting default payment method" do
      user = user_fixture()
      default = create_payment_method_fixture(%{user_id: user.id, is_default: true})
      other = create_payment_method_fixture(%{user_id: user.id, is_default: false})

      assert {:ok, _} = Payments.delete_payment_method(default)
      # Reload other method
      updated = Payments.get_payment_method!(other.id)
      assert updated.is_default == true
    end
  end

  describe "change_payment_method/2" do
    test "returns a changeset" do
      method = create_payment_method_fixture()
      changeset = Payments.change_payment_method(method)
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "deduplicate_payment_methods/1" do
    test "removes duplicate payment methods" do
      user = user_fixture()
      # Create duplicates
      _method1 =
        create_payment_method_fixture(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_duplicate"
        })

      _method2 =
        create_payment_method_fixture(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_duplicate"
        })

      assert {:ok, _kept} = Payments.deduplicate_payment_methods(user)
      methods = Payments.list_payment_methods(user)
      # Should only have one method with this provider_id
      matching = Enum.filter(methods, &(&1.provider_id == "pm_duplicate"))
      assert length(matching) == 1
    end
  end

  describe "set_default_payment_method_if_none/2" do
    test "sets default when user has no default" do
      user = user_fixture()
      method = create_payment_method_fixture(%{user_id: user.id, is_default: false})

      assert {:ok, _} = Payments.set_default_payment_method_if_none(user, method)
      found = Payments.get_default_payment_method(user)
      assert found.id == method.id
    end

    test "does not set default when user already has one" do
      user = user_fixture()
      existing_default = create_payment_method_fixture(%{user_id: user.id, is_default: true})
      new_method = create_payment_method_fixture(%{user_id: user.id, is_default: false})

      assert {:ok, _} = Payments.set_default_payment_method_if_none(user, new_method)
      found = Payments.get_default_payment_method(user)
      assert found.id == existing_default.id
    end
  end

  # Helper function
  defp create_payment_method_fixture(attrs \\ %{}) do
    user = Map.get_lazy(attrs, :user_id, fn -> user_fixture().id end)

    default_attrs = %{
      user_id: user,
      provider: :stripe,
      provider_id: "pm_#{System.unique_integer([:positive])}",
      is_default: false
    }

    {:ok, method} =
      default_attrs
      |> Map.merge(attrs)
      |> Payments.insert_payment_method()

    method
  end
end
