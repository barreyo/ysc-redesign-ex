# Production seeding script
# Run with: mix run priv/repo/seeds_prod.exs
#
# This script seeds essential data for production:
# - SiteSettings (Instagram and Facebook)
# - Admin user for login
# - Default seasons for Tahoe cabin (Winter and Summer)
# - Default seasons for Clear Lake cabin (Winter and Summer)

alias Ysc.Repo
alias Ysc.Accounts.User
alias Ysc.SiteSettings.SiteSetting
alias Ysc.Bookings.Season

IO.puts("🌱 Starting production seed...")

# 1. Seed SiteSettings
IO.puts("📝 Seeding SiteSettings...")

Repo.insert!(
  SiteSetting.site_setting_changeset(%SiteSetting{}, %{
    group: "socials",
    name: "instagram",
    value: "https://www.instagram.com/theysc"
  }),
  on_conflict: :nothing
)

Repo.insert!(
  SiteSetting.site_setting_changeset(%SiteSetting{}, %{
    group: "socials",
    name: "facebook",
    value: "https://www.facebook.com/YoungScandinaviansClub/"
  }),
  on_conflict: :nothing
)

IO.puts("  ✅ SiteSettings seeded")

# 2. Create admin user
IO.puts("👤 Creating admin user...")

admin_user =
  case Repo.get_by(User, email: "admin@ysc.org") do
    nil ->
      admin_changeset =
        User.registration_changeset(%User{}, %{
          email: "admin@ysc.org",
          password: System.get_env("ADMIN_PASSWORD") || "change_me_in_production",
          role: :admin,
          state: :active,
          first_name: "Admin",
          last_name: "User",
          phone_number: "+14159009009",
          most_connected_country: "SE",
          confirmed_at: DateTime.utc_now(),
          registration_form: %{
            membership_type: "family",
            membership_eligibility: ["citizen_of_scandinavia", "born_in_scandinavia"],
            occupation: "Administrator",
            birth_date: "1900-01-01",
            address: "123 Admin St",
            country: "USA",
            city: "San Francisco",
            region: "CA",
            postal_code: "94102",
            place_of_birth: "Sweden",
            citizenship: "USA",
            most_connected_nordic_country: "Sweden",
            link_to_scandinavia: "Administrative role",
            lived_in_scandinavia: "Yes",
            spoken_languages: "English, Swedish",
            hear_about_the_club: "Administrative setup",
            agreed_to_bylaws: "true",
            agreed_to_bylaws_at: DateTime.utc_now(),
            started: DateTime.utc_now(),
            completed: DateTime.utc_now(),
            browser_timezone: "America/Los_Angeles"
          }
        })

      case Repo.insert(admin_changeset, on_conflict: :nothing) do
        {:ok, user} when not is_nil(user) ->
          IO.puts("  ✅ Admin user created: admin@ysc.org")
          user

        {:ok, nil} ->
          # Conflict occurred, fetch the existing user
          existing = Repo.get_by!(User, email: "admin@ysc.org")
          IO.puts("  ℹ️  Admin user already exists: admin@ysc.org")
          existing

        {:error, changeset} ->
          # If insert fails, try to fetch again (might have been created by another process)
          existing = Repo.get_by(User, email: "admin@ysc.org")
          if existing do
            IO.puts("  ℹ️  Admin user already exists: admin@ysc.org")
            existing
          else
            IO.puts("  ❌ Failed to create admin user: #{inspect(changeset.errors)}")
            raise("Failed to create or find admin user")
          end
      end

    existing_user ->
      IO.puts("  ℹ️  Admin user already exists: admin@ysc.org")
      existing_user
  end

# 3. Create seasons for Tahoe cabin
IO.puts("🏔️  Creating seasons for Tahoe cabin...")

# Seasons are recurring annually - we use a base year for the dates, but they repeat every year
# Winter: Nov 1 to April 30 (spans years - recurring pattern)
# Summer: May 1 to October 31 (same year - recurring pattern)
base_year = 2024

# Winter season: Nov 1 to April 30 (year-spanning, recurs annually)
winter_start = Date.new!(base_year, 11, 1)
winter_end = Date.new!(base_year + 1, 4, 30)

# Summer season: May 1 to October 31 (same year, recurs annually)
summer_start = Date.new!(base_year, 5, 1)
summer_end = Date.new!(base_year, 10, 31)

# Tahoe Winter season
tahoe_winter =
  case Repo.get_by(Season, name: "Winter", property: :tahoe) do
    nil ->
      season =
        Season.changeset(%Season{}, %{
          name: "Winter",
          description: "Winter season for Tahoe cabin (Nov 1 - Apr 30, recurring annually)",
          property: :tahoe,
          start_date: winter_start,
          end_date: winter_end,
          is_default: false,
          advance_booking_days: 45,
          max_nights: 4
        })
        |> Repo.insert!()

      IO.puts("  ✅ Created Tahoe Winter season")
      season

    existing ->
      IO.puts("  ℹ️  Tahoe Winter season already exists")
      existing
  end

# Tahoe Summer season
tahoe_summer =
  case Repo.get_by(Season, name: "Summer", property: :tahoe) do
    nil ->
      season =
        Season.changeset(%Season{}, %{
          name: "Summer",
          description: "Summer season for Tahoe cabin (May 1 - Oct 31, recurring annually)",
          property: :tahoe,
          start_date: summer_start,
          end_date: summer_end,
          is_default: true,
          advance_booking_days: nil,
          max_nights: 4
        })
        |> Repo.insert!()

      IO.puts("  ✅ Created Tahoe Summer season")
      season

    existing ->
      IO.puts("  ℹ️  Tahoe Summer season already exists")
      existing
  end

# 4. Create seasons for Clear Lake cabin
IO.puts("🏞️  Creating seasons for Clear Lake cabin...")

# Clear Lake Winter season
clear_lake_winter =
  case Repo.get_by(Season, name: "Winter", property: :clear_lake) do
    nil ->
      season =
        Season.changeset(%Season{}, %{
          name: "Winter",
          description: "Winter season for Clear Lake cabin (Nov 1 - Apr 30, recurring annually)",
          property: :clear_lake,
          start_date: winter_start,
          end_date: winter_end,
          is_default: false,
          advance_booking_days: nil,
          max_nights: 30
        })
        |> Repo.insert!()

      IO.puts("  ✅ Created Clear Lake Winter season")
      season

    existing ->
      IO.puts("  ℹ️  Clear Lake Winter season already exists")
      existing
  end

# Clear Lake Summer season
clear_lake_summer =
  case Repo.get_by(Season, name: "Summer", property: :clear_lake) do
    nil ->
      season =
        Season.changeset(%Season{}, %{
          name: "Summer",
          description: "Summer season for Clear Lake cabin (May 1 - Oct 31, recurring annually)",
          property: :clear_lake,
          start_date: summer_start,
          end_date: summer_end,
          is_default: true,
          advance_booking_days: nil,
          max_nights: 30
        })
        |> Repo.insert!()

      IO.puts("  ✅ Created Clear Lake Summer season")
      season

    existing ->
      IO.puts("  ℹ️  Clear Lake Summer season already exists")
      existing
  end

IO.puts("\n✅ Production seed completed successfully!")
IO.puts("   - SiteSettings: Instagram and Facebook")
IO.puts("   - Admin user: admin@ysc.org")
IO.puts("   - Tahoe seasons: Winter and Summer")
IO.puts("   - Clear Lake seasons: Winter and Summer")
IO.puts("\n⚠️  Note: Make sure to set ADMIN_PASSWORD environment variable in production!")
