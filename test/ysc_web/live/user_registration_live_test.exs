defmodule YscWeb.UserRegistrationLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Registration flow" do
    test "completes full registration process successfully", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      # Step 0: Eligibility
      form = form(lv, "#registration_form")

      # Fill in eligibility information
      step_0_params = %{
        "registration_form" => %{
          "membership_type" => "single",
          "membership_eligibility" => ["born_in_scandinavia", "scandinavian_citizen"]
        }
      }

      render_change(form, %{"user" => step_0_params})

      # Move to next step
      assert render_click(lv, "next-step") =~ "Account Information"

      # Step 1: Personal Information
      step_1_params = %{
        "email" => "test@example.com",
        "password" => "valid_password123",
        "phone_number" => "+14155552671",
        "first_name" => "Test",
        "last_name" => "User",
        "registration_form" => %{
          "birth_date" => "1990-01-01",
          "occupation" => "Software Engineer",
          "address" => "123 Main St",
          "city" => "San Francisco",
          "region" => "CA",
          "country" => "US",
          "postal_code" => "94105"
        }
      }

      render_change(form, %{"user" => step_1_params})

      # Move to next step
      assert render_click(lv, "next-step") =~ "Additional Questions"

      # Step 2: Additional Questions
      step_2_params = %{
        "registration_form" => %{
          "place_of_birth" => "SE",
          "citizenship" => "SE",
          "most_connected_nordic_country" => "SE",
          "link_to_scandinavia" => "Born in Stockholm",
          "lived_in_scandinavia" => "Lived in Stockholm for 20 years",
          "spoken_languages" => "Swedish, Norwegian",
          "hear_about_the_club" => "Through friends",
          "agreed_to_bylaws" => "true"
        }
      }

      render_change(form, %{"user" => step_2_params})

      # Submit the complete form
      {:ok, conn} =
        form
        |> render_submit(%{
          "user" => Map.merge(step_0_params, Map.merge(step_1_params, step_2_params))
        })
        |> follow_redirect(conn, ~p"/users/log-in?_action=registered")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "User created successfully"
    end

    test "validates each step before allowing progression", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      # Try to proceed without filling Step 0
      assert render_click(lv, "next-step") =~ "Eligibility"

      # Fill Step 0 incorrectly
      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "single"
            # Missing membership_eligibility
          }
        }
      })

      assert render_click(lv, "next-step") =~ "Eligibility"

      # Fill Step 0 correctly
      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "single",
            "membership_eligibility" => ["born_in_scandinavia"]
          }
        }
      })

      # Move to Step 1
      assert render_click(lv, "next-step") =~ "Account Information"

      # Try to proceed with invalid email
      render_change(form, %{
        "user" => %{
          "email" => "invalid-email",
          "password" => "short",
          "phone_number" => "invalid"
        }
      })

      assert render_click(lv, "next-step") =~ "Account Information"
      assert render(lv) =~ "must have the @ sign and no spaces"
      assert render(lv) =~ "should be at least 12 character"
    end

    test "handles family membership registration", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      form = form(lv, "#registration_form")

      # Select family membership
      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "family",
            "membership_eligibility" => ["born_in_scandinavia"],
            "family_members" => [
              %{
                "type" => "spouse",
                "first_name" => "Jane",
                "last_name" => "Doe",
                "birth_date" => "1990-01-01"
              }
            ]
          }
        }
      })

      # Verify family member inputs are shown
      assert render_click(lv, "next-step") =~ "Family"
      assert render(lv) =~ "Please list all members of your family"

      # Add family member
      family_params = %{
        "family_members" => [
          %{
            "type" => "spouse",
            "first_name" => "Jane",
            "last_name" => "Doe",
            "birth_date" => "1990-01-01"
          }
        ]
      }

      render_change(form, %{"user" => family_params})
      assert render(lv) =~ "Jane"
      assert render(lv) =~ "Doe"
    end

    test "allows navigation between steps", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      # Fill Step 0
      form = form(lv, "#registration_form")

      render_change(form, %{
        "user" => %{
          "registration_form" => %{
            "membership_type" => "single",
            "membership_eligibility" => ["born_in_scandinavia"]
          }
        }
      })

      # Navigate forward
      assert render_click(lv, "next-step") =~ "Account Information"

      # Navigate back
      assert render_click(lv, "prev-step") =~ "Eligibility"

      # Verify data is preserved
      assert render(lv) =~ "single"
    end
  end
end
