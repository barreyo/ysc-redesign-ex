# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Ysc.Repo.insert!(%Ysc.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Ysc.Repo
alias Ysc.Accounts.User
alias Ysc.SiteSettings.SiteSetting

# Default settings
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

first_names = [
  "Karl",
  "Erik",
  "Lars",
  "Anders",
  "Per",
  "Mikael",
  "Johan",
  "Olof",
  "Nils",
  "Jan",
  "Maria",
  "Elisabeth",
  "Anna",
  "Kristina",
  "Margareta",
  "Eva",
  "Linnéa",
  "Karin",
  "Birgitta",
  "Marie"
]

last_names = [
  "Andersson",
  "Johansson",
  "Karlsson",
  "Nilsson",
  "Eriksson",
  "Larsson",
  "Olsson",
  "Persson",
  "Svensson",
  "Gustafsson",
  "Pettersson",
  "Jonsson",
  "Jansson",
  "Hansson",
  "Bengtsson",
  "Jönsson",
  "Lindberg",
  "Berg",
  "Lind",
  "Lundgren",
  "Lindgren",
  "Sandberg",
  "Eklund"
]

countries = [
  "SE",
  "NO",
  "FI",
  "IS",
  "DK"
]

n_approved_users = 9
n_pending_users = 5
n_rejected_users = 3
n_deleted_users = 2

# Get or create admin user
admin_user =
  case Repo.get_by(User, email: "admin@ysc.org") do
    nil ->
      admin_changeset =
        User.registration_changeset(%User{}, %{
          email: "admin@ysc.org",
          password: "very_secure_password",
          role: :admin,
          state: :active,
          first_name: "Admin",
          last_name: "User",
          phone_number: "+14159009009",
          most_connected_country: countries |> Enum.shuffle() |> hd,
          confirmed_at: DateTime.utc_now(),
          registration_form: %{
            membership_type: "family",
            membership_eligibility: ["citizen_of_scandinavia", "born_in_scandinavia"],
            occupation: "Plumber",
            birth_date: "1900-01-01",
            address: "Dance St 2",
            country: "USA",
            city: "Dance Town",
            region: "CA",
            postal_code: "94700",
            place_of_birth: "Norway",
            citizenship: "USA",
            most_connected_nordic_country: "Norway",
            link_to_scandinavia: "Love it!",
            lived_in_scandinavia: "For a few seconds.",
            spoken_languages: "English and German",
            hear_about_the_club: "On internet",
            agreed_to_bylaws: "true",
            agreed_to_bylaws_at: DateTime.utc_now(),
            started: DateTime.utc_now(),
            completed: DateTime.utc_now(),
            browser_timezone: "America/Los_Angeles"
          }
        })

      case Repo.insert(admin_changeset, on_conflict: :nothing) do
        {:ok, user} when not is_nil(user) ->
          user

        {:ok, nil} ->
          # Conflict occurred, fetch the existing user
          Repo.get_by!(User, email: "admin@ysc.org")

        {:error, _changeset} ->
          # If insert fails, try to fetch again (might have been created by another process)
          Repo.get_by!(User, email: "admin@ysc.org") ||
            raise("Failed to create or find admin user")
      end

    existing_user ->
      existing_user
  end

Enum.each(0..n_approved_users, fn n ->
  membership_type =
    if rem(n, 2) == 0 do
      "single"
    else
      "family"
    end

  last_name = last_names |> Enum.shuffle() |> hd

  fam_members =
    if membership_type == "family" do
      [
        %{
          first_name: first_names |> Enum.shuffle() |> hd,
          last_name: last_name,
          birth_date: "1990-06-06",
          type: "spouse"
        },
        %{
          first_name: first_names |> Enum.shuffle() |> hd,
          last_name: last_name,
          birth_date: "1999-08-08",
          type: "child"
        }
      ]
    else
      []
    end

  first_name = first_names |> Enum.shuffle() |> hd
  email = String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org")

  # Check if user already exists
  existing_user = Repo.get_by(User, email: email)

  if existing_user do
    IO.puts("User already exists, skipping: #{email}")
  else
    regular_user =
      User.registration_changeset(%User{}, %{
        email: email,
        password: "very_secure_password",
        role: :member,
        state: :active,
        first_name: first_name,
        last_name: last_name,
        phone_number: "+1415900900#{n}",
        confirmed_at: DateTime.utc_now(),
        most_connected_country: countries |> Enum.shuffle() |> hd,
        family_members: fam_members,
        registration_form: %{
          membership_type: membership_type,
          membership_eligibility: ["citizen_of_scandinavia", "born_in_scandinavia"],
          occupation: "Plumber",
          birth_date: "1900-01-01",
          address: "Dance St 2",
          country: "USA",
          city: "Dance Town",
          region: "CA",
          postal_code: "94700",
          place_of_birth: "Sweden",
          citizenship: "USA",
          most_connected_nordic_country: "Sweden",
          link_to_scandinavia: "Love it!",
          lived_in_scandinavia: "For a few seconds.",
          spoken_languages: "English and German",
          hear_about_the_club: "On internet",
          agreed_to_bylaws: "true",
          agreed_to_bylaws_at: DateTime.utc_now(),
          started: DateTime.utc_now(),
          completed: DateTime.utc_now(),
          browser_timezone: "America/Los_Angeles",
          reviewed_at: DateTime.utc_now(),
          review_outcome: "approved",
          reviewed_by_user_id: admin_user.id
        }
      })

    case Repo.insert(regular_user, on_conflict: :nothing) do
      {:ok, _user} ->
        :ok

      {:error, changeset} ->
        IO.puts("Failed to create user #{email}: #{inspect(changeset.errors)}")
    end
  end
end)

Enum.each(0..n_pending_users, fn n ->
  membership_type =
    if rem(n, 2) == 0 do
      "single"
    else
      "family"
    end

  last_name = last_names |> Enum.shuffle() |> hd

  fam_members =
    if membership_type == "family" do
      [
        %{
          first_name: first_names |> Enum.shuffle() |> hd,
          last_name: last_name,
          birth_date: "1990-06-06",
          type: "spouse"
        },
        %{
          first_name: first_names |> Enum.shuffle() |> hd,
          last_name: last_name,
          birth_date: "1999-08-08",
          type: "child"
        }
      ]
    else
      []
    end

  first_name = first_names |> Enum.shuffle() |> hd
  email = String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org")

  # Check if user already exists
  existing_user = Repo.get_by(User, email: email)

  if existing_user do
    IO.puts("User already exists, skipping: #{email}")
  else
    pending_user =
      User.registration_changeset(%User{}, %{
        email: email,
        password: "very_secure_password",
        role: :member,
        state: :pending_approval,
        first_name: first_name,
        last_name: last_name,
        phone_number: "+1415900900#{n}",
        confirmed_at: DateTime.utc_now(),
        most_connected_country: countries |> Enum.shuffle() |> hd,
        family_members: fam_members,
        registration_form: %{
          membership_type: membership_type,
          membership_eligibility: ["citizen_of_scandinavia", "born_in_scandinavia"],
          occupation: "Plumber",
          birth_date: "1970-02-04",
          address: "Dance St 2",
          country: "USA",
          city: "Dance Town",
          region: "CA",
          postal_code: "9470#{n}",
          place_of_birth: "Sweden",
          citizenship: "USA",
          most_connected_nordic_country: "Sweden",
          link_to_scandinavia: "Love it!",
          lived_in_scandinavia: "For a few seconds.",
          spoken_languages: "English and German",
          hear_about_the_club: "On internet",
          agreed_to_bylaws: "true",
          agreed_to_bylaws_at: DateTime.utc_now(),
          started: DateTime.utc_now(),
          completed: DateTime.utc_now(),
          browser_timezone: "America/Los_Angeles"
        }
      })

    case Repo.insert(pending_user, on_conflict: :nothing) do
      {:ok, _user} ->
        :ok

      {:error, changeset} ->
        IO.puts("Failed to create user #{email}: #{inspect(changeset.errors)}")
    end
  end
end)

Enum.each(0..n_rejected_users, fn n ->
  first_name = first_names |> Enum.shuffle() |> hd
  last_name = last_names |> Enum.shuffle() |> hd
  email = String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org")

  # Check if user already exists
  existing_user = Repo.get_by(User, email: email)

  if existing_user do
    IO.puts("User already exists, skipping: #{email}")
  else
    rejected_user =
      User.registration_changeset(%User{}, %{
        email: email,
        password: "very_secure_password",
        role: :member,
        state: :rejected,
        first_name: first_name,
        last_name: last_name,
        phone_number: "+1415900900#{n}",
        most_connected_country: countries |> Enum.shuffle() |> hd,
        registration_form: %{
          membership_type: "family",
          membership_eligibiltiy: [],
          occupation: "Plumber",
          birth_date: "1900-01-01",
          address: "Dance St 2",
          country: "USA",
          city: "Dance Town",
          region: "CA",
          postal_code: "94700",
          place_of_birth: "USA",
          citizenship: "USA",
          most_connected_nordic_country: "Iceland",
          link_to_scandinavia: "Love it!",
          lived_in_scandinavia: "For a few seconds.",
          spoken_languages: "English",
          hear_about_the_club: "On internet",
          agreed_to_bylaws: "true",
          agreed_to_bylaws_at: DateTime.utc_now(),
          started: DateTime.utc_now(),
          completed: DateTime.utc_now(),
          browser_timezone: "America/Los_Angeles",
          reviewed_at: DateTime.utc_now(),
          review_outcome: "rejected",
          reviewed_by_user_id: admin_user.id
        }
      })

    case Repo.insert(rejected_user, on_conflict: :nothing) do
      {:ok, _user} ->
        :ok

      {:error, changeset} ->
        IO.puts("Failed to create user #{email}: #{inspect(changeset.errors)}")
    end
  end
end)

Enum.each(0..n_deleted_users, fn n ->
  first_name = first_names |> Enum.shuffle() |> hd
  last_name = last_names |> Enum.shuffle() |> hd
  email = String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org")

  # Check if user already exists
  existing_user = Repo.get_by(User, email: email)

  if existing_user do
    IO.puts("User already exists, skipping: #{email}")
  else
    deleted_user =
      User.registration_changeset(%User{}, %{
        email: email,
        password: "very_secure_password",
        role: :member,
        state: :deleted,
        first_name: first_name,
        last_name: last_name,
        phone_number: "+1415900900#{n}",
        most_connected_country: countries |> Enum.shuffle() |> hd,
        registration_form: %{
          membership_type: "family",
          membership_eligibility: [],
          occupation: "Plumber",
          birth_date: "1970-04-02",
          address: "Dance St 2",
          country: "USA",
          city: "Dance Town",
          region: "CA",
          postal_code: "94700",
          place_of_birth: "USA",
          citizenship: "USA",
          most_connected_nordic_country: "Iceland",
          link_to_scandinavia: "Love it!",
          lived_in_scandinavia: "For a few seconds.",
          spoken_languages: "English",
          hear_about_the_club: "On internet",
          agreed_to_bylaws: "true",
          agreed_to_bylaws_at: DateTime.utc_now(),
          started: DateTime.utc_now(),
          completed: DateTime.utc_now(),
          browser_timezone: "America/Los_Angeles",
          reviewed_at: DateTime.utc_now(),
          review_outcome: "approved",
          reviewed_by_user_id: admin_user.id
        }
      })

    case Repo.insert(deleted_user, on_conflict: :nothing) do
      {:ok, _user} ->
        :ok

      {:error, changeset} ->
        IO.puts("Failed to create user #{email}: #{inspect(changeset.errors)}")
    end
  end
end)

# Seed Posts and Events with Images
import Ecto.Query
alias Ysc.Posts
alias Ysc.Posts.Post
alias Ysc.Events
alias Ysc.Events.Event
alias Ysc.Events.TicketTier
alias Ysc.Media
alias Ysc.Media.Image
alias Ysc.Agendas

# Get active users for creating posts and events
active_users = Repo.all(from u in User, where: u.state == :active, limit: 10)

if length(active_users) > 0 do
  # Seed directory for images
  seed_assets_dir = Path.join([File.cwd!(), "etc", "seed", "assets"])

  # Upload images to S3 and create Image records
  # Use admin_user for image creation since it requires admin role
  uploaded_images =
    if File.exists?(seed_assets_dir) do
      seed_assets_dir
      |> File.ls!()
      |> Enum.filter(&String.contains?(&1, [".jpg", ".jpeg", ".png", ".webp"]))
      |> Enum.with_index()
      |> Enum.map(fn {filename, index} ->
        image_path = Path.join(seed_assets_dir, filename)

        image_title =
          String.replace(filename, ~r/[_-]/, " ") |> String.replace(~r/\.[^.]*$/, "")

        # Check if image already exists by title
        existing_image =
          Repo.one(
            from i in Image,
              where: i.title == ^image_title,
              limit: 1
          )

        if existing_image do
          IO.puts("Image already exists, skipping: #{filename}")
          existing_image
        else
          # Upload raw file to S3
          upload_result =
            try do
              Media.upload_file_to_s3(image_path)
            rescue
              e ->
                IO.puts("Failed to upload #{filename} to S3: #{inspect(e)}")
                nil
            end

          if upload_result do
            raw_s3_path = upload_result[:body][:location]

            # Check if image with this raw_image_path already exists
            existing_by_path =
              Repo.one(
                from i in Image,
                  where: i.raw_image_path == ^URI.encode(raw_s3_path),
                  limit: 1
              )

            if existing_by_path do
              IO.puts("Image with path already exists, skipping: #{filename}")
              existing_by_path
            else
              # Create image record (must use admin_user for authorization)
              case Media.add_new_image(
                     %{
                       raw_image_path: URI.encode(raw_s3_path),
                       user_id: admin_user.id,
                       title: image_title,
                       processing_state: "unprocessed"
                     },
                     admin_user
                   ) do
                {:ok, new_image} ->
                  # Process the image (create thumbnails, optimized versions, blur hash)
                  temp_dir = "/tmp/image_processor"
                  File.mkdir_p!(temp_dir)
                  tmp_output_file = "#{temp_dir}/#{new_image.id}"
                  optimized_output_path = "#{tmp_output_file}_optimized.png"
                  thumbnail_output_path = "#{tmp_output_file}_thumb.png"

                  processed_image =
                    try do
                      Media.process_image_upload(
                        new_image,
                        image_path,
                        thumbnail_output_path,
                        optimized_output_path
                      )
                    rescue
                      e ->
                        # If image processing fails, at least we have the raw image
                        IO.puts("Failed to process image #{filename}: #{inspect(e)}")
                        new_image
                    end

                  # Clean up temp files
                  try do
                    File.rm_rf(temp_dir)
                  rescue
                    _ -> :ok
                  end

                  processed_image

                {:error, reason} ->
                  IO.puts("Failed to create image record for #{filename}: #{inspect(reason)}")
                  nil
              end
            end
          else
            nil
          end
        end
      end)
      |> Enum.filter(&(&1 != nil))
    else
      []
    end

  if length(uploaded_images) > 0 do
    IO.puts("Uploaded #{length(uploaded_images)} images to S3")

    # Create example posts
    post_titles = [
      "Welcome to the Young Scandinavians Club",
      "Annual Midsummer Celebration Coming Up",
      "Scandinavian Cooking Class: Traditional Recipes",
      "Hiking Trip to Yosemite National Park",
      "Nordic Book Club: February Selection"
    ]

    post_contents = [
      """
      We're excited to welcome all new members to the Young Scandinavians Club!

      Our club has been fostering connections among young Scandinavians living in the Bay Area for over a decade. We organize regular events, cultural activities, and provide a supportive community for Scandinavians away from home.

      Whether you're from Sweden, Norway, Denmark, Finland, or Iceland, you'll find a warm welcome here. Join us for our upcoming events and meet fellow Scandinavians!
      """,
      """
      Join us for our annual Midsummer celebration! This is one of our most popular events of the year.

      **Event Details:**
      - Traditional midsummer pole raising
      - Folk dancing and music
      - Traditional Scandinavian food
      - Activities for all ages

      Don't miss this opportunity to celebrate Scandinavian traditions with friends and family!
      """,
      """
      Learn to cook traditional Scandinavian dishes in our hands-on cooking class.

      In this class, you'll learn to make:
      - Swedish meatballs
      - Norwegian salmon
      - Danish pastries
      - Finnish cinnamon buns

      All ingredients provided. Bring your appetite and curiosity!
      """,
      """
      Explore the great outdoors with fellow club members on our annual hiking trip to Yosemite.

      We'll be hiking some of the most beautiful trails, sharing stories, and enjoying nature. This is a great way to connect with other outdoor enthusiasts in the club.

      All experience levels welcome!
      """,
      """
      This month's book club selection is "Beartown" by Fredrik Backman.

      Join us for a lively discussion about this acclaimed Swedish novel. Whether you've read it before or it's your first time, all perspectives are welcome.

      We meet on the last Thursday of each month. Coffee and pastries provided!
      """
    ]

    Enum.each(0..(length(post_titles) - 1), fn index ->
      title = Enum.at(post_titles, index)

      try do
        # Check if post already exists by title
        existing_post = Repo.one(from p in Post, where: p.title == ^title, limit: 1)

        if existing_post do
          IO.puts("Post already exists, skipping: #{title}")
        else
          content = Enum.at(post_contents, index)
          # Use admin_user for post creation since it requires admin role
          user = admin_user
          image = Enum.at(uploaded_images, rem(index, length(uploaded_images)))

          url_name =
            title
            |> String.downcase()
            |> String.replace(~r/[^a-z0-9]+/, "-")
            |> String.trim("-")
            |> then(fn name -> "#{name}-#{System.system_time(:second) - index}" end)

          published_on = DateTime.add(DateTime.utc_now(), -index * 2, :day)

          case Posts.create_post(
                 %{
                   "title" => title,
                   "url_name" => url_name,
                   "raw_body" => content,
                   "rendered_body" => content,
                   "preview_text" => String.slice(content, 0..150) <> "...",
                   "state" => "published",
                   "image_id" => image.id,
                   "featured_post" => index == 0,
                   "published_on" => published_on
                 },
                 user
               ) do
            {:ok, post} ->
              IO.puts("Created post: #{post.title}")

            {:error, changeset} ->
              IO.puts("Failed to create post: #{title} - #{inspect(changeset.errors)}")
          end
        end
      rescue
        e ->
          IO.puts("Error creating post '#{title}': #{inspect(e)}")
      end
    end)

    # Helper function to generate agenda items based on event type
    generate_agenda_items = fn event_title, start_time, end_time ->
      # Extract hour from start_time
      start_hour = start_time.hour
      start_minute = start_time.minute
      end_hour = end_time.hour
      end_minute = end_time.minute

      # Calculate total duration in minutes
      total_minutes = end_hour * 60 + end_minute - (start_hour * 60 + start_minute)

      # Generate agenda items based on event type
      items =
        cond do
          String.contains?(String.downcase(event_title), "gala") or
              String.contains?(String.downcase(event_title), "dinner") ->
            [
              %{title: "Welcome Reception", description: "Cocktails and mingling", duration: 30},
              %{
                title: "Opening Remarks",
                description: "Welcome address from club leadership",
                duration: 15
              },
              %{title: "First Course", description: "Traditional appetizers", duration: 25},
              %{title: "Main Course", description: "Scandinavian specialties", duration: 45},
              %{title: "Entertainment", description: "Live music and performances", duration: 40},
              %{
                title: "Dessert & Coffee",
                description: "Traditional desserts and coffee service",
                duration: 30
              },
              %{
                title: "Closing Remarks",
                description: "Thank you and announcements",
                duration: 10
              }
            ]

          String.contains?(String.downcase(event_title), "book") ->
            [
              %{
                title: "Welcome & Introductions",
                description: "Meet fellow readers",
                duration: 15
              },
              %{
                title: "Book Discussion",
                description: "Deep dive into this month's selection",
                duration: 60
              },
              %{title: "Q&A Session", description: "Questions and sharing", duration: 20},
              %{
                title: "Next Month Preview",
                description: "Introduction to next month's book",
                duration: 10
              }
            ]

          String.contains?(String.downcase(event_title), "cultural") ->
            [
              %{
                title: "Welcome & Registration",
                description: "Check-in and welcome refreshments",
                duration: 30
              },
              %{
                title: "Opening Presentation",
                description: "Introduction to Scandinavian culture",
                duration: 20
              },
              %{
                title: "Food & Drink Tasting",
                description: "Sample traditional Scandinavian cuisine",
                duration: 45
              },
              %{
                title: "Cultural Activities",
                description: "Interactive workshops and demonstrations",
                duration: 60
              },
              %{
                title: "Music & Dancing",
                description: "Traditional music and folk dancing",
                duration: 40
              },
              %{
                title: "Closing & Networking",
                description: "Final remarks and networking",
                duration: 15
              }
            ]

          String.contains?(String.downcase(event_title), "festival") ->
            [
              %{
                title: "Opening Ceremony",
                description: "Welcome and festival kickoff",
                duration: 20
              },
              %{
                title: "Morning Activities",
                description: "Games, crafts, and activities for all ages",
                duration: 120
              },
              %{title: "Lunch Break", description: "Food vendors and picnic areas", duration: 60},
              %{
                title: "Afternoon Entertainment",
                description: "Live music and performances",
                duration: 150
              },
              %{title: "Evening Program", description: "Main stage performances", duration: 120},
              %{
                title: "Closing Celebration",
                description: "Final remarks and fireworks",
                duration: 30
              }
            ]

          String.contains?(String.downcase(event_title), "wine") ->
            [
              %{
                title: "Welcome Reception",
                description: "Registration and welcome wine",
                duration: 20
              },
              %{
                title: "Introduction to Scandinavian Wines",
                description: "Overview of Nordic wine regions",
                duration: 30
              },
              %{
                title: "First Flight Tasting",
                description: "Three white wines with tasting notes",
                duration: 30
              },
              %{
                title: "Second Flight Tasting",
                description: "Three red wines with pairing suggestions",
                duration: 30
              },
              %{
                title: "Cheese & Charcuterie Pairing",
                description: "Small plates paired with wines",
                duration: 40
              },
              %{
                title: "Q&A with Sommelier",
                description: "Questions and final recommendations",
                duration: 20
              }
            ]

          String.contains?(String.downcase(event_title), "hiking") ->
            [
              %{
                title: "Meet & Greet",
                description: "Meet at trailhead, introductions",
                duration: 15
              },
              %{
                title: "Trail Briefing",
                description: "Safety briefing and route overview",
                duration: 10
              },
              %{
                title: "Hike to First Viewpoint",
                description: "Moderate hike with scenic views",
                duration: 90
              },
              %{
                title: "Rest & Snack Break",
                description: "Break time with provided snacks",
                duration: 20
              },
              %{
                title: "Continue to Summit",
                description: "Continue to main viewpoint",
                duration: 60
              },
              %{title: "Lunch Break", description: "Lunch at scenic location", duration: 45},
              %{title: "Return Hike", description: "Return to trailhead", duration: 90},
              %{
                title: "Closing & Departure",
                description: "Final remarks and departure",
                duration: 10
              }
            ]

          String.contains?(String.downcase(event_title), "language") ->
            [
              %{
                title: "Welcome & Introductions",
                description: "Meet fellow language learners",
                duration: 20
              },
              %{
                title: "Swedish Conversation Circle",
                description: "Practice Swedish with native speakers",
                duration: 30
              },
              %{
                title: "Norwegian Conversation Circle",
                description: "Practice Norwegian with native speakers",
                duration: 30
              },
              %{
                title: "Danish Conversation Circle",
                description: "Practice Danish with native speakers",
                duration: 30
              },
              %{
                title: "Language Exchange Mixer",
                description: "Open conversation time",
                duration: 30
              },
              %{
                title: "Closing & Next Steps",
                description: "Resources and next meeting info",
                duration: 10
              }
            ]

          true ->
            # Generic agenda for other events
            [
              %{
                title: "Welcome & Registration",
                description: "Check-in and welcome",
                duration: 15
              },
              %{title: "Opening Remarks", description: "Introduction and overview", duration: 10},
              %{
                title: "Main Program",
                description: "Featured activities and presentations",
                duration: max(30, div(total_minutes - 50, 2))
              },
              %{title: "Break", description: "Networking and refreshments", duration: 15},
              %{
                title: "Continued Program",
                description: "Additional activities",
                duration: max(30, div(total_minutes - 50, 2))
              },
              %{title: "Closing", description: "Final remarks and announcements", duration: 10}
            ]
        end

      # Convert to time-based agenda items
      current_minute = start_hour * 60 + start_minute

      items
      |> Enum.filter(fn item -> item.duration <= total_minutes end)
      |> Enum.reduce_while({[], current_minute}, fn item, {acc, current} ->
        if current + item.duration <= end_hour * 60 + end_minute do
          item_start_hour = div(current, 60)
          item_start_minute = rem(current, 60)
          item_end_minute = current + item.duration
          item_end_hour = div(item_end_minute, 60)
          item_end_minute = rem(item_end_minute, 60)

          agenda_item = %{
            title: item.title,
            description: item.description,
            start_time: Time.new!(item_start_hour, item_start_minute, 0),
            end_time: Time.new!(item_end_hour, item_end_minute, 0)
          }

          {:cont, {[agenda_item | acc], current + item.duration}}
        else
          {:halt, {acc, current}}
        end
      end)
      |> elem(0)
      |> Enum.reverse()
    end

    # Create example events
    # Mix of free events and events with paid tickets
    event_data = [
      # Free events
      %{
        title: "Scandinavian Cultural Evening",
        description: "Join us for an evening of Scandinavian culture, food, and music",
        start_date: DateTime.add(DateTime.utc_now(), 30, :day),
        start_time: ~T[18:00:00],
        end_date: DateTime.add(DateTime.utc_now(), 30, :day),
        end_time: ~T[22:00:00],
        location_name: "Scandinavian Community Center",
        address: "123 Main St, San Francisco, CA 94102",
        latitude: 37.7749,
        longitude: -122.4194,
        max_attendees: 100,
        ticket_tiers: [
          %{name: "General Admission", type: :free, quantity: 100}
        ]
      },
      %{
        title: "Nordic Book Discussion",
        description: "Monthly book club meeting discussing Nordic literature",
        start_date: DateTime.add(DateTime.utc_now(), 45, :day),
        start_time: ~T[19:00:00],
        end_date: DateTime.add(DateTime.utc_now(), 45, :day),
        end_time: ~T[21:00:00],
        location_name: "Public Library",
        address: "456 Library Ave, San Francisco, CA 94103",
        latitude: 37.7849,
        longitude: -122.4094,
        max_attendees: 25,
        ticket_tiers: [
          %{name: "Member Admission", type: :free, quantity: 25}
        ]
      },
      # Paid events
      %{
        title: "Scandinavian Gala Dinner",
        description: "Elegant dinner featuring traditional Scandinavian cuisine",
        start_date: DateTime.add(DateTime.utc_now(), 60, :day),
        start_time: ~T[19:00:00],
        end_date: DateTime.add(DateTime.utc_now(), 60, :day),
        end_time: ~T[23:00:00],
        location_name: "Grand Ballroom",
        address: "789 Event Blvd, San Francisco, CA 94104",
        latitude: 37.7949,
        longitude: -122.3994,
        max_attendees: 150,
        ticket_tiers: [
          %{
            name: "Early Bird",
            type: :paid,
            price: Money.new(7500, :USD),
            quantity: 50,
            description: "Save $25!"
          },
          %{name: "Regular Ticket", type: :paid, price: Money.new(10000, :USD), quantity: 100}
        ]
      },
      %{
        title: "Wine Tasting: Scandinavian Varietals",
        description: "Sample wines from Scandinavian producers with expert sommeliers",
        start_date: DateTime.add(DateTime.utc_now(), 75, :day),
        start_time: ~T[17:00:00],
        end_date: DateTime.add(DateTime.utc_now(), 75, :day),
        end_time: ~T[20:00:00],
        location_name: "Wine Cellar",
        address: "321 Vineyard St, Napa, CA 94558",
        latitude: 38.2975,
        longitude: -122.2869,
        max_attendees: 40,
        ticket_tiers: [
          %{name: "Member Price", type: :paid, price: Money.new(4500, :USD), quantity: 20},
          %{name: "Non-Member Price", type: :paid, price: Money.new(6000, :USD), quantity: 20}
        ]
      },
      # Events with both free and paid tiers
      %{
        title: "Summer Festival 2024",
        description: "Our biggest event of the year! Music, food, games, and more",
        start_date: DateTime.add(DateTime.utc_now(), 90, :day),
        start_time: ~T[10:00:00],
        end_date: DateTime.add(DateTime.utc_now(), 90, :day),
        end_time: ~T[22:00:00],
        location_name: "Golden Gate Park",
        address: "1000 Park Blvd, San Francisco, CA 94117",
        latitude: 37.7694,
        longitude: -122.4862,
        max_attendees: 500,
        ticket_tiers: [
          %{
            name: "Free Admission",
            type: :free,
            quantity: 300,
            description: "General admission to the festival"
          },
          %{
            name: "VIP Pass",
            type: :paid,
            price: Money.new(15000, :USD),
            quantity: 100,
            description: "Includes VIP area access and premium food"
          },
          %{
            name: "Family Pack",
            type: :paid,
            price: Money.new(20000, :USD),
            quantity: 50,
            description: "Up to 4 people"
          }
        ]
      },
      %{
        title: "Hiking Day Trip: Marin Headlands",
        description: "Guided hiking trip with picnic lunch included",
        start_date: DateTime.add(DateTime.utc_now(), 50, :day),
        start_time: ~T[08:00:00],
        end_date: DateTime.add(DateTime.utc_now(), 50, :day),
        end_time: ~T[18:00:00],
        location_name: "Marin Headlands Trailhead",
        address: "Marin Headlands, Sausalito, CA 94965",
        latitude: 37.8267,
        longitude: -122.4991,
        max_attendees: 30,
        ticket_tiers: [
          %{name: "Free (Bring Your Own Lunch)", type: :free, quantity: 15},
          %{
            name: "With Lunch",
            type: :paid,
            price: Money.new(2500, :USD),
            quantity: 15,
            description: "Includes catered picnic lunch"
          }
        ]
      },
      # Another free event
      %{
        title: "Language Exchange Meetup",
        description: "Practice your Scandinavian languages with native speakers",
        start_date: DateTime.add(DateTime.utc_now(), 20, :day),
        start_time: ~T[18:30:00],
        end_date: DateTime.add(DateTime.utc_now(), 20, :day),
        end_time: ~T[20:30:00],
        location_name: "Community Center",
        address: "555 Community Way, Berkeley, CA 94704",
        latitude: 37.8715,
        longitude: -122.2730,
        max_attendees: 50,
        ticket_tiers: [
          %{name: "Free Admission", type: :free, quantity: 50}
        ]
      }
    ]

    Enum.each(event_data, fn event_attrs ->
      try do
        # Check if event already exists by title
        existing_event = Repo.one(from e in Event, where: e.title == ^event_attrs.title, limit: 1)

        if existing_event do
          IO.puts("Event already exists, skipping: #{event_attrs.title}")

          # Still try to create agenda if it doesn't exist
          try do
            existing_agendas = Agendas.list_agendas_for_event(existing_event.id)

            if length(existing_agendas) == 0 do
              # Use existing event's times if available, fallback to event_attrs
              start_time = existing_event.start_time || event_attrs.start_time
              end_time = existing_event.end_time || event_attrs.end_time
              agenda_items = generate_agenda_items.(existing_event.title, start_time, end_time)

              if length(agenda_items) > 0 do
                case Agendas.create_agenda(existing_event, %{title: "Event Agenda"}) do
                  {:ok, agenda} ->
                    items_created =
                      Enum.reduce(agenda_items, 0, fn item_attrs, count ->
                        case Agendas.create_agenda_item(existing_event.id, agenda, item_attrs) do
                          {:ok, _agenda_item} ->
                            count + 1

                          {:error, changeset} ->
                            IO.puts(
                              "  Failed to create agenda item '#{item_attrs.title}': #{inspect(changeset.errors)}"
                            )

                            count
                        end
                      end)

                    IO.puts(
                      "  Created agenda with #{items_created} agenda item(s) for existing event '#{existing_event.title}'"
                    )

                  {:error, changeset} ->
                    IO.puts(
                      "  Failed to create agenda for existing event '#{existing_event.title}': #{inspect(changeset.errors)}"
                    )
                end
              end
            end
          rescue
            e ->
              IO.puts(
                "  Error creating agenda for existing event '#{existing_event.title}': #{inspect(e)}"
              )
          end
        else
          # Use admin_user for event creation since it requires admin role
          organizer = admin_user
          image = Enum.random(uploaded_images)

          # Calculate publish_at (before start_date)
          publish_at = DateTime.add(event_attrs.start_date, -7, :day)

          case Events.create_event(%{
                 state: "published",
                 organizer_id: organizer.id,
                 title: event_attrs.title,
                 description: event_attrs.description,
                 image_id: image.id,
                 start_date: event_attrs.start_date,
                 start_time: event_attrs.start_time,
                 end_date: event_attrs.end_date,
                 end_time: event_attrs.end_time,
                 location_name: event_attrs.location_name,
                 address: event_attrs.address,
                 latitude: event_attrs.latitude,
                 longitude: event_attrs.longitude,
                 max_attendees: event_attrs.max_attendees,
                 unlimited_capacity: false,
                 published_at: publish_at,
                 publish_at: publish_at,
                 raw_details: """
                 <p>A wonderful serenity has taken possession of my entire soul, like these sweet mornings of spring which I enjoy with my whole heart. I am alone, and feel the charm of existence in this spot, which was created for the bliss of souls like mine.</p>
                 <p>I am so happy, my dear friend, so absorbed in the exquisite sense of mere tranquil existence, that I neglect my talents. I should be incapable of drawing a single stroke at the present moment; and yet I feel that I never was a greater artist than now.</p>
                 <p>When, while the lovely valley teems with vapour around me, and the meridian sun strikes the upper surface of the impenetrable foliage of my trees, and but a few stray gleams steal into the inner sanctuary, I throw myself down among the tall grass by the trickling stream; and, as I lie close to the earth, a thousand unknown plants are noticed by me: when I hear the buzz of the little world among the stalks, and grow familiar with the countless indescribable forms of the insects and flies, then I feel the presence of the Almighty, who formed us in his own image, and the breath</p>
                 <p>We hope to see you there!</p>
                 """,
                 rendered_details: """
                 <p>A wonderful serenity has taken possession of my entire soul, like these sweet mornings of spring which I enjoy with my whole heart. I am alone, and feel the charm of existence in this spot, which was created for the bliss of souls like mine.</p>
                 <p>I am so happy, my dear friend, so absorbed in the exquisite sense of mere tranquil existence, that I neglect my talents. I should be incapable of drawing a single stroke at the present moment; and yet I feel that I never was a greater artist than now.</p>
                 <p>When, while the lovely valley teems with vapour around me, and the meridian sun strikes the upper surface of the impenetrable foliage of my trees, and but a few stray gleams steal into the inner sanctuary, I throw myself down among the tall grass by the trickling stream; and, as I lie close to the earth, a thousand unknown plants are noticed by me: when I hear the buzz of the little world among the stalks, and grow familiar with the countless indescribable forms of the insects and flies, then I feel the presence of the Almighty, who formed us in his own image, and the breath</p>
                 <p>We hope to see you there!</p>
                 """
               }) do
            {:ok, event} ->
              # Create ticket tiers for the event
              Enum.each(event_attrs.ticket_tiers, fn tier_attrs ->
                tier_name = tier_attrs.name

                # Check if ticket tier already exists for this event
                existing_tier =
                  Repo.one(
                    from tt in Ysc.Events.TicketTier,
                      where: tt.event_id == ^event.id and tt.name == ^tier_name,
                      limit: 1
                  )

                if existing_tier do
                  IO.puts(
                    "Ticket tier '#{tier_name}' already exists for event '#{event.title}', skipping"
                  )
                else
                  case Events.create_ticket_tier(Map.merge(tier_attrs, %{event_id: event.id})) do
                    {:ok, _tier} ->
                      :ok

                    {:error, changeset} ->
                      IO.puts(
                        "Failed to create ticket tier '#{tier_name}': #{inspect(changeset.errors)}"
                      )
                  end
                end
              end)

              # Create agenda with agenda items
              try do
                # Check if agenda already exists for this event
                existing_agendas = Agendas.list_agendas_for_event(event.id)

                if length(existing_agendas) > 0 do
                  IO.puts("  Agenda already exists for '#{event.title}', skipping")
                else
                  # Generate agenda items based on event type
                  agenda_items =
                    generate_agenda_items.(
                      event.title,
                      event_attrs.start_time,
                      event_attrs.end_time
                    )

                  if length(agenda_items) > 0 do
                    # Create the agenda
                    case Agendas.create_agenda(event, %{title: "Event Agenda"}) do
                      {:ok, agenda} ->
                        # Create agenda items
                        items_created =
                          Enum.reduce(agenda_items, 0, fn item_attrs, count ->
                            case Agendas.create_agenda_item(event.id, agenda, item_attrs) do
                              {:ok, _agenda_item} ->
                                count + 1

                              {:error, changeset} ->
                                IO.puts(
                                  "  Failed to create agenda item '#{item_attrs.title}': #{inspect(changeset.errors)}"
                                )

                                count
                            end
                          end)

                        IO.puts(
                          "  Created agenda with #{items_created} agenda item(s) for '#{event.title}'"
                        )

                      {:error, changeset} ->
                        IO.puts(
                          "  Failed to create agenda for '#{event.title}': #{inspect(changeset.errors)}"
                        )
                    end
                  else
                    IO.puts("  No agenda items generated for '#{event.title}' (event too short)")
                  end
                end
              rescue
                e ->
                  IO.puts("  Error creating agenda for '#{event.title}': #{inspect(e)}")
              end

              IO.puts(
                "Created event: #{event.title} (#{length(event_attrs.ticket_tiers)} ticket tier(s))"
              )

            {:error, changeset} ->
              IO.puts(
                "Failed to create event: #{event_attrs.title} - #{inspect(changeset.errors)}"
              )
          end
        end
      rescue
        e ->
          IO.puts("Error creating event '#{event_attrs.title}': #{inspect(e)}")
      end
    end)

    IO.puts("\n✅ Seed completed successfully!")
    IO.puts("   - #{length(uploaded_images)} images uploaded to S3")
    IO.puts("   - Posts and events checked/created")
  else
    IO.puts("⚠️  No images found in #{seed_assets_dir}. Skipping posts and events creation.")
  end
else
  IO.puts("⚠️  No active users found. Please create users first before seeding posts and events.")
end
