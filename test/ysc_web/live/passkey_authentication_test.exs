defmodule YscWeb.PasskeyAuthenticationTest do
  @moduledoc """
  Comprehensive tests for passkey authentication flow.
  """
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.UserPasskey

  setup %{conn: conn} do
    user = user_fixture()
    {:ok, user} = Accounts.mark_email_verified(user)

    %{conn: conn, user: user}
  end

  describe "Passkey authentication - challenge creation" do
    test "creates authentication challenge when sign_in_with_passkey is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Click sign in with passkey button
      lv
      |> element("button[phx-click='sign_in_with_passkey']")
      |> render_click()

      # Verify challenge was created
      assert %{passkey_challenge: challenge} = lv.assigns
      assert challenge != nil
      assert challenge.rp_id == "localhost"
      assert challenge.origin == "http://localhost:4002"
      assert byte_size(challenge.bytes) >= 16

      # Verify loading state
      assert lv.assigns.passkey_loading == true

      # Verify create_authentication_challenge event was pushed
      assert_push_event(lv, "create_authentication_challenge", %{options: options})
      assert options["challenge"] != nil
      assert options["rpId"] == "localhost"
      assert options["userVerification"] == "preferred"
      # Should not have allowCredentials for discoverable credentials
      refute Map.has_key?(options, "allowCredentials")
    end

    test "includes all passkeys in challenge for Wax verification", %{conn: conn, user: user} do
      # Create a passkey for the user
      credential_id = :crypto.strong_rand_bytes(16)

      public_key_map = %{
        -3 => :crypto.strong_rand_bytes(32),
        -2 => :crypto.strong_rand_bytes(32),
        -1 => 1,
        1 => 2,
        3 => -7
      }

      {:ok, _passkey} =
        Accounts.create_user_passkey(user, %{
          external_id: credential_id,
          public_key: UserPasskey.encode_public_key(public_key_map),
          nickname: "Test Device"
        })

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Click sign in with passkey
      lv
      |> element("button[phx-click='sign_in_with_passkey']")
      |> render_click()

      # Challenge should include the passkey in allow_credentials for Wax
      challenge = lv.assigns.passkey_challenge
      assert challenge != nil
      assert length(challenge.allow_credentials) == 1
      {stored_credential_id, _stored_public_key} = List.first(challenge.allow_credentials)
      assert stored_credential_id == credential_id
    end
  end

  describe "Passkey authentication - verification" do
    setup %{user: user} do
      passkey = create_test_passkey(user)
      %{passkey: passkey, credential_id: passkey.external_id}
    end

    test "handles missing challenge gracefully", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Try to verify without creating challenge first
      response = %{
        "id" => "test",
        "rawId" => "test",
        "type" => "public-key",
        "response" => %{
          "authenticatorData" => "test",
          "clientDataJSON" => "test",
          "signature" => "test",
          "userHandle" => "test"
        }
      }

      lv
      |> element("form")
      |> render_hook("verify_authentication", response)

      # Should show error about expired session
      assert lv.assigns.flash[:error] =~ "expired" ||
               lv.assigns.flash[:error] =~ "session"

      assert lv.assigns.passkey_loading == false
    end

    test "handles passkey not found error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Create challenge
      lv
      |> element("button[phx-click='sign_in_with_passkey']")
      |> render_click()

      # Use a non-existent credential ID
      fake_credential_id = :crypto.strong_rand_bytes(16)
      fake_raw_id = Base.url_encode64(fake_credential_id, padding: false)

      response = %{
        "id" => fake_raw_id,
        "rawId" => fake_raw_id,
        "type" => "public-key",
        "response" => %{
          "authenticatorData" => Base.url_encode64(:crypto.strong_rand_bytes(37), padding: false),
          "clientDataJSON" =>
            Base.url_encode64(
              Jason.encode!(%{
                type: "webauthn.get",
                challenge: "",
                origin: "http://localhost:4002"
              }),
              padding: false
            ),
          "signature" => Base.url_encode64(:crypto.strong_rand_bytes(64), padding: false),
          "userHandle" => Base.url_encode64("fake_user_id", padding: false)
        }
      }

      lv
      |> element("form")
      |> render_hook("verify_authentication", response)

      # Should show error about invalid passkey
      assert lv.assigns.flash[:error] =~ "Invalid passkey" ||
               lv.assigns.flash[:error] =~ "not found"

      assert lv.assigns.passkey_loading == false
    end

    test "handles missing userHandle for discoverable credentials", %{
      conn: conn,
      user: user,
      passkey: passkey
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Create challenge
      lv
      |> element("button[phx-click='sign_in_with_passkey']")
      |> render_click()

      raw_id = Base.url_encode64(passkey.external_id, padding: false)
      challenge = lv.assigns.passkey_challenge

      response = %{
        "id" => raw_id,
        "rawId" => raw_id,
        "type" => "public-key",
        "response" => %{
          "authenticatorData" => Base.url_encode64(:crypto.strong_rand_bytes(37), padding: false),
          "clientDataJSON" =>
            Base.url_encode64(
              Jason.encode!(%{
                type: "webauthn.get",
                challenge: Base.url_encode64(challenge.bytes, padding: false),
                origin: "http://localhost:4002"
              }),
              padding: false
            ),
          "signature" => Base.url_encode64(:crypto.strong_rand_bytes(64), padding: false),
          "userHandle" => nil
        }
      }

      lv
      |> element("form")
      |> render_hook("verify_authentication", response)

      # Should show error about missing userHandle
      assert lv.assigns.flash[:error] =~ "Invalid passkey response" ||
               lv.assigns.flash[:error] =~ "userHandle"

      assert lv.assigns.passkey_loading == false
    end

    test "handles user ID mismatch for discoverable credentials", %{
      conn: conn,
      user: user,
      passkey: passkey
    } do
      # Create another user
      other_user = user_fixture()
      {:ok, other_user} = Accounts.mark_email_verified(other_user)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Create challenge
      lv
      |> element("button[phx-click='sign_in_with_passkey']")
      |> render_click()

      raw_id = Base.url_encode64(passkey.external_id, padding: false)
      challenge = lv.assigns.passkey_challenge
      # Use wrong user's ID in userHandle
      wrong_user_id = Base.url_encode64(other_user.id, padding: false)

      response = %{
        "id" => raw_id,
        "rawId" => raw_id,
        "type" => "public-key",
        "response" => %{
          "authenticatorData" => Base.url_encode64(:crypto.strong_rand_bytes(37), padding: false),
          "clientDataJSON" =>
            Base.url_encode64(
              Jason.encode!(%{
                type: "webauthn.get",
                challenge: Base.url_encode64(challenge.bytes, padding: false),
                origin: "http://localhost:4002"
              }),
              padding: false
            ),
          "signature" => Base.url_encode64(:crypto.strong_rand_bytes(64), padding: false),
          "userHandle" => wrong_user_id
        }
      }

      lv
      |> element("form")
      |> render_hook("verify_authentication", response)

      # Should show error about user ID mismatch
      assert lv.assigns.flash[:error] =~ "mismatch" ||
               lv.assigns.flash[:error] =~ "Invalid"

      assert lv.assigns.passkey_loading == false
    end

    test "handles credential ID mismatch", %{conn: conn, user: user, passkey: passkey} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Create challenge
      lv
      |> element("button[phx-click='sign_in_with_passkey']")
      |> render_click()

      # Use wrong credential ID
      wrong_credential_id = :crypto.strong_rand_bytes(16)
      wrong_raw_id = Base.url_encode64(wrong_credential_id, padding: false)
      challenge = lv.assigns.passkey_challenge
      user_id = Base.url_encode64(user.id, padding: false)

      response = %{
        "id" => wrong_raw_id,
        "rawId" => wrong_raw_id,
        "type" => "public-key",
        "response" => %{
          "authenticatorData" => Base.url_encode64(:crypto.strong_rand_bytes(37), padding: false),
          "clientDataJSON" =>
            Base.url_encode64(
              Jason.encode!(%{
                type: "webauthn.get",
                challenge: Base.url_encode64(challenge.bytes, padding: false),
                origin: "http://localhost:4002"
              }),
              padding: false
            ),
          "signature" => Base.url_encode64(:crypto.strong_rand_bytes(64), padding: false),
          "userHandle" => user_id
        }
      }

      lv
      |> element("form")
      |> render_hook("verify_authentication", response)

      # Should show error about invalid passkey
      assert lv.assigns.flash[:error] =~ "Invalid passkey" ||
               lv.assigns.flash[:error] =~ "not found"

      assert lv.assigns.passkey_loading == false
    end

    test "handles passkey authentication errors from JavaScript", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Create challenge
      lv
      |> element("button[phx-click='sign_in_with_passkey']")
      |> render_click()

      # Simulate error from JavaScript
      lv
      |> element("form")
      |> render_hook("passkey_auth_error", %{
        "error" => "NotAllowedError",
        "message" => "User cancelled the operation"
      })

      # Should show error message
      assert lv.assigns.flash[:error] != nil
      assert lv.assigns.passkey_loading == false
      assert lv.assigns.passkey_challenge == nil
    end

    test "shows loading state during authentication", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/log-in")

      # Initially not loading
      refute html =~ "Signing in..."

      # Click sign in with passkey
      lv
      |> element("button[phx-click='sign_in_with_passkey']")
      |> render_click()

      # Should show loading state
      html = render(lv)
      assert html =~ "Signing in..." || html =~ "opacity-50"
      assert lv.assigns.passkey_loading == true
    end
  end

  describe "Passkey authentication - sign count validation" do
    setup %{user: user} do
      %{user: user}
    end

    test "allows first use when sign_count is 0", %{conn: conn, user: user} do
      # Create a new passkey with sign_count = 0
      credential_id = :crypto.strong_rand_bytes(16)

      public_key_map = %{
        -3 => :crypto.strong_rand_bytes(32),
        -2 => :crypto.strong_rand_bytes(32),
        -1 => 1,
        1 => 2,
        3 => -7
      }

      {:ok, passkey} =
        Accounts.create_user_passkey(user, %{
          external_id: credential_id,
          public_key: UserPasskey.encode_public_key(public_key_map),
          nickname: "New Device",
          sign_count: 0
        })

      # The sign count check should allow 0 >= 0 for first use
      assert passkey.sign_count == 0

      # Verify the passkey can be updated with same sign_count (first use)
      assert {:ok, _updated} = Accounts.update_passkey_sign_count(passkey, 0)
    end
  end

  describe "Passkey authentication - multiple passkeys" do
    setup %{user: user} do
      %{user: user}
    end

    test "handles multiple passkeys for same user", %{conn: conn, user: user} do
      # Create multiple passkeys
      credential_id1 = :crypto.strong_rand_bytes(16)
      credential_id2 = :crypto.strong_rand_bytes(16)

      public_key_map = %{
        -3 => :crypto.strong_rand_bytes(32),
        -2 => :crypto.strong_rand_bytes(32),
        -1 => 1,
        1 => 2,
        3 => -7
      }

      {:ok, _passkey1} =
        Accounts.create_user_passkey(user, %{
          external_id: credential_id1,
          public_key: UserPasskey.encode_public_key(public_key_map),
          nickname: "Device 1"
        })

      {:ok, _passkey2} =
        Accounts.create_user_passkey(user, %{
          external_id: credential_id2,
          public_key: UserPasskey.encode_public_key(public_key_map),
          nickname: "Device 2"
        })

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Create challenge - should include both passkeys
      lv
      |> element("button[phx-click='sign_in_with_passkey']")
      |> render_click()

      challenge = lv.assigns.passkey_challenge
      assert challenge != nil
      assert length(challenge.allow_credentials) == 2
    end

    test "handles passkeys from different users", %{conn: conn, user: _user} do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, user1} = Accounts.mark_email_verified(user1)
      {:ok, user2} = Accounts.mark_email_verified(user2)

      credential_id1 = :crypto.strong_rand_bytes(16)
      credential_id2 = :crypto.strong_rand_bytes(16)

      public_key_map = %{
        -3 => :crypto.strong_rand_bytes(32),
        -2 => :crypto.strong_rand_bytes(32),
        -1 => 1,
        1 => 2,
        3 => -7
      }

      {:ok, _passkey1} =
        Accounts.create_user_passkey(user1, %{
          external_id: credential_id1,
          public_key: UserPasskey.encode_public_key(public_key_map),
          nickname: "User1 Device"
        })

      {:ok, _passkey2} =
        Accounts.create_user_passkey(user2, %{
          external_id: credential_id2,
          public_key: UserPasskey.encode_public_key(public_key_map),
          nickname: "User2 Device"
        })

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Create challenge - should include both users' passkeys
      lv
      |> element("button[phx-click='sign_in_with_passkey']")
      |> render_click()

      challenge = lv.assigns.passkey_challenge
      assert challenge != nil
      assert length(challenge.allow_credentials) == 2
    end
  end

  describe "Passkey authentication - UI states" do
    test "shows passkey button when supported", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/log-in")

      # Simulate passkey support
      lv
      |> element("form")
      |> render_hook("passkey_support_detected", %{"supported" => true})

      html = render(lv)
      assert html =~ "Sign in with Passkey" || html =~ "passkey"
    end

    test "hides passkey button when not supported", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      # Simulate no passkey support
      lv
      |> element("form")
      |> render_hook("passkey_support_detected", %{"supported" => false})

      html = render(lv)
      refute html =~ "Sign in with Passkey"
    end
  end
end
