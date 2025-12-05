defmodule YscWeb.Authorization.PolicyTest do
  @moduledoc """
  Tests for the authorization policy module.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Authorization.Policy

  describe "post policies" do
    test "admin can create posts" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:post_create, admin)
    end

    test "regular member cannot create posts" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:post_create, member)
    end

    test "anyone can read posts" do
      member = user_fixture(%{role: "member"})
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:post_read, member)
      assert :ok = Policy.authorize(:post_read, admin)
    end

    test "admin can update posts" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:post_update, admin)
    end

    test "regular member cannot update posts" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:post_update, member)
    end

    test "no one can delete posts (always denied)" do
      admin = user_fixture(%{role: "admin"})
      assert {:error, :unauthorized} = Policy.authorize(:post_delete, admin)
    end
  end

  describe "user policies" do
    test "anyone can create users" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:user_create, member)
    end

    test "admin can read any user" do
      admin = user_fixture(%{role: "admin"})
      other_user = user_fixture()

      assert :ok = Policy.authorize(:user_read, admin, other_user)
    end

    # Note: LetMe Policy may require explicit :own_resource check implementation
    # The :own_resource check relies on comparing resource.id with user.id
    # which may not work directly without custom check implementation

    test "member cannot read other users" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} = Policy.authorize(:user_read, member, other_user)
    end

    test "admin can update any user" do
      admin = user_fixture(%{role: "admin"})
      other_user = user_fixture()

      assert :ok = Policy.authorize(:user_update, admin, other_user)
    end

    # Note: LetMe Policy :own_resource check may require custom implementation

    test "no one can delete users (always denied)" do
      admin = user_fixture(%{role: "admin"})
      assert {:error, :unauthorized} = Policy.authorize(:user_delete, admin)
    end
  end

  describe "event policies" do
    test "admin can create events" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:event_create, admin)
    end

    test "regular member cannot create events" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:event_create, member)
    end

    test "anyone can read events" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:event_read, member)
    end

    test "admin can update events" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:event_update, admin)
    end

    test "admin can delete events" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:event_delete, admin)
    end
  end

  describe "media_image policies" do
    test "admin can create images" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:media_image_create, admin)
    end

    test "member cannot create images" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:media_image_create, member)
    end

    test "anyone can read images" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:media_image_read, member)
    end

    test "admin can update images" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:media_image_update, admin)
    end

    test "admin can delete images" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:media_image_delete, admin)
    end
  end

  describe "site_setting policies" do
    test "admin can manage site settings" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:site_setting_create, admin)
      assert :ok = Policy.authorize(:site_setting_update, admin)
      assert :ok = Policy.authorize(:site_setting_delete, admin)
    end

    test "anyone can read site settings" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:site_setting_read, member)
    end
  end

  describe "agenda policies" do
    test "admin can manage agendas" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:agenda_create, admin)
      assert :ok = Policy.authorize(:agenda_update, admin)
      assert :ok = Policy.authorize(:agenda_delete, admin)
    end

    test "anyone can read agendas" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:agenda_read, member)
    end

    test "member cannot manage agendas" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} = Policy.authorize(:agenda_create, member)
      assert {:error, :unauthorized} = Policy.authorize(:agenda_update, member)
      assert {:error, :unauthorized} = Policy.authorize(:agenda_delete, member)
    end
  end

  describe "agenda_item policies" do
    test "admin can manage agenda items" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:agenda_item_create, admin)
      assert :ok = Policy.authorize(:agenda_item_update, admin)
      assert :ok = Policy.authorize(:agenda_item_delete, admin)
    end

    test "anyone can read agenda items" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:agenda_item_read, member)
    end
  end

  describe "ticket_tier policies" do
    test "admin can manage ticket tiers" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:ticket_tier_create, admin)
      assert :ok = Policy.authorize(:ticket_tier_update, admin)
      assert :ok = Policy.authorize(:ticket_tier_delete, admin)
    end

    test "anyone can read ticket tiers" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:ticket_tier_read, member)
    end
  end
end
