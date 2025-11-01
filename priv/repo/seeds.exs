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

      Repo.insert!(admin_changeset)

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

  regular_user =
    User.registration_changeset(%User{}, %{
      email: String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org"),
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

  Repo.insert!(
    regular_user,
    on_conflict: :nothing
  )
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

  pending_user =
    User.registration_changeset(%User{}, %{
      email: String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org"),
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

  Repo.insert!(
    pending_user,
    on_conflict: :nothing
  )
end)

Enum.each(0..n_rejected_users, fn n ->
  first_name = first_names |> Enum.shuffle() |> hd
  last_name = last_names |> Enum.shuffle() |> hd

  rejected_user =
    User.registration_changeset(%User{}, %{
      email: String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org"),
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

  Repo.insert!(
    rejected_user,
    on_conflict: :nothing
  )
end)

Enum.each(0..n_deleted_users, fn n ->
  first_name = first_names |> Enum.shuffle() |> hd
  last_name = last_names |> Enum.shuffle() |> hd

  deleted_user =
    User.registration_changeset(%User{}, %{
      email: String.downcase("#{first_name}_#{last_name}_#{n}@ysc.org"),
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

  Repo.insert!(
    deleted_user,
    on_conflict: :nothing
  )
end)

# Seed Posts and Events with Images
import Ecto.Query
alias Ysc.Posts
alias Ysc.Posts.Post
alias Ysc.Events
alias Ysc.Events.Event
alias Ysc.Media
alias Ysc.Media.Image

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

        # Upload raw file to S3
        upload_result = Media.upload_file_to_s3(image_path)
        raw_s3_path = upload_result[:body][:location]

        # Create image record (must use admin_user for authorization)
        case Media.add_new_image(
               %{
                 raw_image_path: URI.encode(raw_s3_path),
                 user_id: admin_user.id,
                 title:
                   String.replace(filename, ~r/[_-]/, " ") |> String.replace(~r/\.[^.]*$/, ""),
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
                _ ->
                  # If image processing fails, at least we have the raw image
                  new_image
              end

            # Clean up temp files
            File.rm_rf(temp_dir)

            processed_image

          {:error, reason} ->
            IO.puts("Failed to create image record for #{filename}: #{inspect(reason)}")
            nil
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
    end)

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
      # Check if event already exists by title
      existing_event = Repo.one(from e in Event, where: e.title == ^event_attrs.title, limit: 1)

      if existing_event do
        IO.puts("Event already exists, skipping: #{event_attrs.title}")
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
               ## #{event_attrs.title}

               #{event_attrs.description}

               ### Event Details

               **Location:** #{event_attrs.location_name}
               **Address:** #{event_attrs.address}
               **Date:** #{Calendar.strftime(event_attrs.start_date, "%B %d, %Y")}
               **Time:** #{Time.to_string(event_attrs.start_time)} - #{Time.to_string(event_attrs.end_time)}

               We hope to see you there!
               """,
               rendered_details: """
               <h2>#{event_attrs.title}</h2>
               <p>#{event_attrs.description}</p>
               <h3>Event Details</h3>
               <p><strong>Location:</strong> #{event_attrs.location_name}<br>
               <strong>Address:</strong> #{event_attrs.address}<br>
               <strong>Date:</strong> #{Calendar.strftime(event_attrs.start_date, "%B %d, %Y")}<br>
               <strong>Time:</strong> #{Time.to_string(event_attrs.start_time)} - #{Time.to_string(event_attrs.end_time)}</p>
               <p>We hope to see you there!</p>
               """
             }) do
          {:ok, event} ->
            # Create ticket tiers for the event
            Enum.each(event_attrs.ticket_tiers, fn tier_attrs ->
              case Events.create_ticket_tier(Map.merge(tier_attrs, %{event_id: event.id})) do
                {:ok, _tier} ->
                  :ok

                {:error, changeset} ->
                  IO.puts("Failed to create ticket tier: #{inspect(changeset.errors)}")
              end
            end)

            IO.puts(
              "Created event: #{event.title} (#{length(event_attrs.ticket_tiers)} ticket tier(s))"
            )

          {:error, changeset} ->
            IO.puts("Failed to create event: #{event_attrs.title} - #{inspect(changeset.errors)}")
        end
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
