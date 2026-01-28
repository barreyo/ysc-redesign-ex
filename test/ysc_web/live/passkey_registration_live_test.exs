defmodule YscWeb.PasskeyRegistrationLiveTest do
  @moduledoc """
  Comprehensive tests for passkey registration flow.
  """
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.UserPasskey
  alias Ysc.Repo

  setup :register_and_log_in_user

  describe "Passkey registration page" do
    test "renders registration page for authenticated user", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/users/settings/passkeys/new")

      assert html =~ "Add a Passkey to Your Account"
      assert html =~ "Use your device's fingerprint or face scan to sign in faster"
    end

    test "redirects unauthenticated users to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/users/settings/passkeys/new")
      assert path == ~p"/users/log-in"
    end
  end

  describe "Passkey registration flow" do
    test "creates authentication challenge when create_passkey is clicked", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/passkeys/new")

      # Click the create passkey button
      lv
      |> element("button[phx-click='create_passkey']")
      |> render_click()

      # Verify challenge was created and assigned
      assert %{passkey_challenge: challenge} = lv.assigns
      assert challenge != nil
      assert challenge.rp_id == "localhost"
      assert challenge.origin == "http://localhost:4002"
      assert byte_size(challenge.bytes) >= 16

      # Verify loading state is set
      assert lv.assigns.loading == true

      # Verify create_registration_challenge event was pushed
      assert_push_event(lv, "create_registration_challenge", %{options: options})
      assert options["challenge"] != nil
      assert options["rp"]["id"] == "localhost"
      assert options["user"]["id"] != nil
      assert options["user"]["name"] == user.email
    end

    test "handles challenge creation failure gracefully", %{conn: conn} do
      # Temporarily break Wax config to cause failure
      original_rp_id = Application.get_env(:wax_, :rp_id)
      Application.put_env(:wax_, :rp_id, nil)

      {:ok, lv, _html} = live(conn, ~p"/users/settings/passkeys/new")

      # Click create passkey - should handle error
      lv
      |> element("button[phx-click='create_passkey']")
      |> render_click()

      # Restore config
      Application.put_env(:wax_, :rp_id, original_rp_id)

      # Should show error or handle gracefully
      assert lv.assigns.loading == false
    end

    test "handles invalid WebAuthn response gracefully", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/passkeys/new")

      # Create challenge first
      lv
      |> element("button[phx-click='create_passkey']")
      |> render_click()

      # Get the challenge from assigns
      challenge = lv.assigns.passkey_challenge
      assert challenge != nil

      # Create an invalid WebAuthn response (invalid attestation object)
      credential_id = :crypto.strong_rand_bytes(16)
      # Too short to be valid
      invalid_attestation_object = :crypto.strong_rand_bytes(50)

      client_data_json =
        Jason.encode!(%{
          type: "webauthn.create",
          challenge: Base.url_encode64(challenge.bytes, padding: false),
          origin: "http://localhost:4002"
        })

      response = %{
        "id" => Base.url_encode64(credential_id, padding: false),
        "rawId" => Base.url_encode64(credential_id, padding: false),
        "type" => "public-key",
        "response" => %{
          "attestationObject" => Base.url_encode64(invalid_attestation_object, padding: false),
          "clientDataJSON" => Base.url_encode64(client_data_json, padding: false)
        }
      }

      # This will fail because the attestation object is invalid
      lv
      |> element("form")
      |> render_hook("verify_registration", response)

      # Should handle the error gracefully
      assert lv.assigns.loading == false
      assert lv.assigns.error != nil
      assert lv.assigns.passkey_challenge == nil
    end

    test "handles passkey registration errors", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/passkeys/new")

      # Create challenge first
      lv
      |> element("button[phx-click='create_passkey']")
      |> render_click()

      # Simulate a registration error from JavaScript
      lv
      |> element("form")
      |> render_hook("passkey_registration_error", %{
        "error" => "NotAllowedError",
        "message" => "User cancelled the operation"
      })

      # Should show error message
      assert lv.assigns.error != nil
      assert lv.assigns.loading == false
      assert lv.assigns.passkey_challenge == nil
    end

    test "handles expired challenge", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/passkeys/new")

      # Create challenge
      lv
      |> element("button[phx-click='create_passkey']")
      |> render_click()

      # Clear the challenge (simulating expiration)
      lv = assign(lv, :passkey_challenge, nil)

      # Try to verify with no challenge
      response = %{
        "id" => "test",
        "rawId" => "test",
        "type" => "public-key",
        "response" => %{
          "attestationObject" => "test",
          "clientDataJSON" => "test"
        }
      }

      lv
      |> element("form")
      |> render_hook("verify_registration", response)

      # Should show expiration error
      assert lv.assigns.error =~ "expired"
      assert lv.assigns.loading == false
    end

    test "shows loading state during passkey creation", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/settings/passkeys/new")

      # Initially not loading
      refute html =~ "Creating Passkey..."

      # Click create passkey
      lv
      |> element("button[phx-click='create_passkey']")
      |> render_click()

      # Should show loading state
      html = render(lv)
      assert html =~ "Creating Passkey..." || html =~ "opacity-50"
    end
  end

  describe "Passkey support detection" do
    test "detects passkey support and updates UI", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/passkeys/new")

      # Simulate passkey support detection
      lv
      |> element("form")
      |> render_hook("passkey_support_detected", %{"supported" => true})

      assert lv.assigns.passkey_supported == true
    end

    test "hides create button when passkeys not supported", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings/passkeys/new")

      # Simulate no passkey support
      lv
      |> element("form")
      |> render_hook("passkey_support_detected", %{"supported" => false})

      html = render(lv)
      refute html =~ "Create Passkey"
    end
  end
end
