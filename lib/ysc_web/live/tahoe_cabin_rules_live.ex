defmodule YscWeb.TahoeCabinRulesLive do
  use YscWeb, :live_view
  use YscNative, :live_view

  alias Ysc.Bookings

  @impl true
  def mount(_params, _session, socket) do
    categories = get_categories()
    rules_data = get_rules_data()
    selected_category = List.first(categories)[:id]

    rules_json = Jason.encode!(%{categories: categories, rules: rules_data})

    socket =
      socket
      |> assign(:selected_category, selected_category)
      |> assign(:rules_json, rules_json)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    category = Map.get(params, "category", socket.assigns.selected_category)
    {:noreply, assign(socket, :selected_category, category)}
  end

  @impl true
  def handle_event("select_category", %{"category" => category}, socket) do
    {:noreply,
     socket
     |> assign(:selected_category, category)
     |> push_patch(to: ~p"/cabin-rules?category=#{category}")}
  end

  @impl true
  def handle_event("native_nav", %{"to" => to}, socket) do
    allowed =
      MapSet.new([
        "/",
        "/property-check-in",
        "/bookings/tahoe",
        "/bookings/tahoe/staying-with",
        "/bookings/clear-lake",
        "/cabin-rules"
      ])

    if MapSet.member?(allowed, to) do
      {:noreply, push_navigate(socket, to: to)}
    else
      {:noreply, socket}
    end
  end

  defp get_categories do
    [
      %{id: "welcome", title: "Welcome", icon: "house.fill"},
      %{id: "trash", title: "Trash & Recycling", icon: "trash.fill"},
      %{id: "kitchen", title: "Kitchen & Cooking", icon: "fork.knife"},
      %{id: "bears", title: "Bear & Wildlife", icon: "pawprint.fill"},
      %{id: "quiet", title: "Quiet Hours", icon: "moon.fill"},
      %{id: "heating", title: "Heating & Logs", icon: "flame.fill"},
      %{id: "checkout", title: "Check-out", icon: "checkmark.circle.fill"},
      %{id: "emergency", title: "Emergency", icon: "phone.fill"}
    ]
  end

  defp get_rules_data do
    %{
      "welcome" => get_welcome_rules(),
      "trash" => get_trash_rules(),
      "kitchen" => get_kitchen_rules(),
      "bears" => get_bear_rules(),
      "quiet" => get_quiet_hours_rules(),
      "heating" => get_heating_rules(),
      "checkout" => get_checkout_rules(),
      "emergency" => get_emergency_rules()
    }
  end

  defp get_welcome_rules do
    [
      %{
        title: "TL;DR",
        content:
          "Wi-Fi: Welcome2024! | Payment required before arrival | Bring your own linens & towels"
      },
      %{
        title: "Wi-Fi Password",
        content: "Network: YSC-Tahoe | Password: Welcome2024!"
      },
      %{
        title: "Payment Required",
        content:
          "Payment for the member and all guests must be completed in advance on the website before your arrival date. You cannot show up at the cabin without payment."
      },
      %{
        title: "What to Bring",
        content:
          "⚠️ CRITICAL: Linens and towels are NOT provided. You must bring your own bedding, sheets, pillowcases, towels, and sleeping bags. Bring your own food - the kitchen is fully equipped with appliances and spices, but you must provide all ingredients."
      },
      %{
        title: "Parking",
        content:
          "Parking is extremely limited. Carpooling is strongly encouraged. No street parking allowed from November 1 through May 1. During check-in, you'll be asked to provide vehicle information to help coordinate parking."
      }
    ]
  end

  defp get_trash_rules do
    [
      %{
        title: "TL;DR",
        content:
          "All trash must be in bear-proof bins with lids secured. Remove all food before checkout."
      },
      %{
        title: "Bear-Proof Garbage",
        content:
          "Use bear-proof lids on all garbage cans at all times. Secure bear-proof garbage lids before leaving. Bears are attracted to food smells, so proper trash management is critical for safety."
      },
      %{
        title: "Disposal",
        content:
          "Properly dispose of all trash before checkout. Remove all food from the refrigerator. All trash must be in the metal bins with lids secured."
      }
    ]
  end

  defp get_kitchen_rules do
    [
      %{
        title: "TL;DR",
        content:
          "Fully equipped kitchen with spices. Bring your own food. Leave spotless before checkout."
      },
      %{
        title: "Kitchen Equipment",
        content:
          "The kitchen is fully equipped with all necessary appliances and cookware. Spices are available for your use."
      },
      %{
        title: "Food Storage",
        content:
          "Bring your own food. All ingredients must be provided by you. Remove all food from the refrigerator before checkout."
      },
      %{
        title: "Cleaning Requirements",
        content:
          "Leave the kitchen spotless before checkout. This includes washing all dishes, cleaning countertops, and removing all food items."
      },
      %{
        title: "Shared Fridge Space",
        content:
          "Be considerate of other guests when using the refrigerator. Label your food items and remove them before checkout."
      }
    ]
  end

  defp get_bear_rules do
    [
      %{
        title: "TL;DR",
        content:
          "Electric bear wire protects the cabin. Always turn OFF before entering/exiting. Wait 5 seconds after turning off."
      },
      %{
        title: "Bear Safety & The Electric Wire",
        content:
          "The cabin is protected by an electric bear wire. It is safe if handled correctly, but can deliver a shock if touched while active."
      },
      %{
        title: "Entering the Cabin",
        content:
          "To enter safely: 1) Locate the switch box near the entrance, 2) Turn OFF the bear wire, 3) Wait 5 seconds, 4) Enter the property, 5) Turn the wire back ON after entering."
      },
      %{
        title: "Leaving the Cabin",
        content:
          "When leaving: 1) Turn OFF the bear wire at the switch box, 2) Wait 5 seconds, 3) Exit the property, 4) Turn the wire back ON after exiting."
      },
      %{
        title: "Important Reminders",
        content:
          "Never touch the wire when it's ON. Always turn it OFF before entering or exiting. The wire protects the cabin from bears - keep it active when not entering/exiting."
      },
      %{
        title: "Trash and Bears",
        content:
          "Use bear-proof lids on all garbage cans at all times. Bears are attracted to food smells, so proper trash management is critical for safety."
      }
    ]
  end

  defp get_quiet_hours_rules do
    [
      %{
        title: "TL;DR",
        content:
          "Quiet hours: 10:00 PM to 7:00 AM. Stairs and hallways carry sound easily - step lightly."
      },
      %{
        title: "Quiet Hours",
        content:
          "Respect quiet hours from 10:00 PM to 7:00 AM. Please step lightly on the stairs, as they carry sound easily."
      },
      %{
        title: "General Guidelines",
        content:
          "Treat the cabin as your own — it's not a hotel. Be considerate of other guests and respect shared spaces."
      },
      %{
        title: "Common Areas & Storage",
        content:
          "Keep personal items out of shared spaces. Store ski boots in the laundry room racks. Store other gear in the outside stairwell. Do not clutter common areas."
      },
      %{
        title: "Consideration",
        content:
          "Be considerate — stairs and hallways carry sound easily. Keep noise levels down, especially during quiet hours."
      },
      %{
        title: "Children",
        content:
          "For safety and noise, children are not permitted to play on or near the stairs. Please supervise children at all times to ensure they respect quiet hours."
      }
    ]
  end

  defp get_heating_rules do
    [
      %{
        title: "TL;DR",
        content:
          "Wood is provided but may be damp. Bring fire starter/kindling and some dry wood to start the stove."
      },
      %{
        title: "Fire-Starting",
        content:
          "Bring fire starter/kindling and some dry wood to start the stove. Wood is provided but may be damp."
      },
      %{
        title: "Heating System",
        content:
          "The cabin has a wood stove for heating. Make sure the fire is completely extinguished before leaving. Never leave a fire unattended."
      }
    ]
  end

  defp get_checkout_rules do
    [
      %{
        title: "TL;DR",
        content: "Checkout is at 11:00 AM. Complete all cleaning tasks before leaving."
      },
      %{
        title: "Checkout Time",
        content:
          "Checkout is at 11:00 AM. Please ensure you have completed all required cleaning before this time."
      },
      %{
        title: "Checklist",
        content:
          "□ Strip the beds and clean your room\n□ Wash, dry, and fold any used club bedding\n□ Leave the kitchen spotless (wash all dishes, clean countertops)\n□ Remove all food from the refrigerator\n□ Secure bear-proof garbage lids\n□ Turn off all lights\n□ Ensure fire is completely extinguished (if used)\n□ Turn bear wire back ON if you turned it off"
      },
      %{
        title: "Why It Matters",
        content:
          "Keeping the cabin affordable depends on everyone pitching in! Your cooperation helps keep cabin rates low for all members."
      }
    ]
  end

  defp get_emergency_rules do
    [
      %{
        title: "TL;DR",
        content: "For emergencies, contact the club manager. No pets allowed. No smoking indoors."
      },
      %{
        title: "Club Manager",
        content: "For urgent issues, contact the club manager through the website or app."
      },
      %{
        title: "No Pets Policy",
        content: "No pets are allowed — no exceptions. This policy is strictly enforced."
      },
      %{
        title: "No Smoking or Vaping",
        content:
          "Smoking and vaping are prohibited indoors and on covered decks. This policy is strictly enforced."
      },
      %{
        title: "Local Services",
        content:
          "Emergency services: 911\nFor non-emergency issues, contact the club manager through the website."
      }
    ]
  end

  # Keep old methods for backward compatibility but they won't be used
  defp get_old_rules_data do
    %{
      "booking" => get_booking_rules(),
      "refund" => get_refund_policy_rules(),
      "trash" => [
        %{
          title: "Bear-Proof Garbage",
          content:
            "Use bear-proof lids on all garbage cans at all times. Secure bear-proof garbage lids before leaving."
        },
        %{
          title: "Disposal",
          content:
            "Properly dispose of all trash before checkout. Remove all food from the refrigerator."
        }
      ],
      "bears" => [
        %{
          title: "Bear Safety & The Electric Wire",
          content:
            "The cabin is protected by an electric bear wire. It is safe if handled correctly, but can deliver a shock if touched while active."
        },
        %{
          title: "Entering the Cabin",
          content:
            "To enter safely: 1) Locate the switch box near the entrance, 2) Turn OFF the bear wire, 3) Wait 5 seconds, 4) Enter the property, 5) Turn the wire back ON after entering."
        },
        %{
          title: "Leaving the Cabin",
          content:
            "When leaving: 1) Turn OFF the bear wire at the switch box, 2) Wait 5 seconds, 3) Exit the property, 4) Turn the wire back ON after exiting."
        },
        %{
          title: "Important Reminders",
          content:
            "Never touch the wire when it's ON. Always turn it OFF before entering or exiting. The wire protects the cabin from bears - keep it active when not entering/exiting."
        },
        %{
          title: "Trash and Bears",
          content:
            "Use bear-proof lids on all garbage cans at all times. Bears are attracted to food smells, so proper trash management is critical for safety."
        }
      ],
      "checkout" => [
        %{
          title: "Checkout Time",
          content:
            "Checkout is at 11:00 AM. Please ensure you have completed all required cleaning before this time."
        },
        %{
          title: "Required Cleaning",
          content:
            "Guests must clean up after themselves, strip and clean their rooms, wash/dry/store any used club bedding, leave the kitchen spotless and remove all food, and secure bear-proof garbage lids."
        },
        %{
          title: "Kitchen",
          content: "Leave the kitchen spotless and remove all food from the refrigerator."
        },
        %{
          title: "Rooms",
          content: "Clean your room and strip the beds."
        },
        %{
          title: "Laundry",
          content: "If you use club bedding, you must wash, dry, and fold it before leaving."
        },
        %{
          title: "Why It Matters",
          content:
            "Keeping the cabin affordable depends on everyone pitching in! Your cooperation helps keep cabin rates low for all members."
        }
      ],
      "kitchen" => [
        %{
          title: "Kitchen Equipment",
          content:
            "The kitchen is fully equipped with all necessary appliances and cookware. Spices are available for your use."
        },
        %{
          title: "Food Storage",
          content:
            "Bring your own food. All ingredients must be provided by you. Remove all food from the refrigerator before checkout."
        },
        %{
          title: "Cleaning Requirements",
          content:
            "Leave the kitchen spotless before checkout. This includes washing all dishes, cleaning countertops, and removing all food items."
        },
        %{
          title: "What's Provided",
          content:
            "A full kitchen with appliances, cookware, and basic spices are available. You must bring all food ingredients."
        }
      ],
      "parking" => [
        %{
          title: "Limited Parking",
          content:
            "Parking is extremely limited. Carpooling is strongly encouraged to reduce parking strain and environmental impact."
        },
        %{
          title: "Street Parking Ban",
          content:
            "No street parking allowed from November 1 through May 1. During this period, you must use the designated parking areas only."
        },
        %{
          title: "Parking Rules",
          content:
            "Limited parking — carpool if possible. Be considerate of other guests and only use the space you need."
        },
        %{
          title: "Vehicle Information",
          content:
            "During check-in, you'll be asked to provide vehicle information (type, color, make) to help coordinate parking with other guests."
        }
      ],
      "etiquette" => [
        %{
          title: "General Guidelines",
          content:
            "Treat the cabin as your own — it's not a hotel. Be considerate of other guests and respect shared spaces."
        },
        %{
          title: "Quiet Hours",
          content:
            "Respect quiet hours from 10:00 PM to 7:00 AM. Please step lightly on the stairs, as they carry sound easily."
        },
        %{
          title: "Common Areas & Storage",
          content:
            "Keep personal items out of shared spaces. Store ski boots in the laundry room racks. Store other gear in the outside stairwell. Do not clutter common areas."
        },
        %{
          title: "Consideration",
          content:
            "Be considerate — stairs and hallways carry sound easily. Keep noise levels down, especially during quiet hours."
        }
      ],
      "what_to_bring" => [
        %{
          title: "Critical: Linens and Towels",
          content:
            "⚠️ Linens and towels are NOT provided. You must bring your own bedding and towels for your stay."
        },
        %{
          title: "Bedding",
          content:
            "You must bring your own sheets, pillowcases, towels, and sleeping bags. None are provided."
        },
        %{
          title: "Towels",
          content: "Bring towels for showers and the sauna. None are provided."
        },
        %{
          title: "Food",
          content:
            "Bring your own food. A full kitchen and spices are available, but you must provide all ingredients."
        },
        %{
          title: "Fire-Starting",
          content:
            "Bring fire starter/kindling and some dry wood to start the stove. Wood is provided but may be damp."
        }
      ],
      "pets" => [
        %{
          title: "No Pets Policy",
          content: "No pets are allowed — no exceptions. This policy is strictly enforced."
        }
      ],
      "smoking" => [
        %{
          title: "No Smoking or Vaping",
          content:
            "Smoking and vaping are prohibited indoors and on covered decks. This policy is strictly enforced."
        }
      ],
      "children" => [
        %{
          title: "Safety Rules",
          content:
            "For safety and noise, children are not permitted to play on or near the stairs. Please supervise children at all times."
        },
        %{
          title: "Consideration",
          content:
            "Children should be supervised to ensure they respect quiet hours and don't disturb other guests."
        }
      ]
    }
  end

  defp get_booking_rules do
    [
      %{
        title: "Advance Payment Required",
        content:
          "All reservations must be made and paid in advance on the website. Payment is required at the time of booking. Payment for the member and all guests must be completed before you arrive at the cabin."
      },
      %{
        title: "Payment for All Guests",
        content:
          "You must pay for yourself (the member) AND every guest who will be staying with you. Payment is determined by the total number of people staying, including all guests. Do not show up at the cabin if you have not paid for all guests in advance."
      },
      %{
        title: "One Active Reservation",
        content:
          "You are only allowed to have one active reservation per membership at any given time."
      },
      %{
        title: "Single Membership - Winter Season",
        content:
          "Single membership holders can only reserve 1 room during winter season (December through April)."
      },
      %{
        title: "Family Membership - Winter Season",
        content:
          "Family membership holders are allowed to reserve 2 rooms for the same stay during winter season. Both rooms must be reserved for the same dates."
      },
      %{
        title: "Accurate Guest Count",
        content:
          "Please make sure you specify the correct number of people, including ALL guests, that will be staying in the room(s) with you. Payment is determined by number of guests, not a fixed rate per room. You must pay for everyone who will be staying."
      },
      %{
        title: "Making New Reservations",
        content: "When your current stay is completed, another reservation can be made."
      },
      %{
        title: "Cancellation Processing Fee",
        content:
          "Cash refunds due to cancellations are subject to a 3% processing fee to cover the club's credit card handling costs."
      }
    ]
  end

  defp get_refund_policy_rules do
    case Bookings.get_active_refund_policy(:tahoe, :room) do
      nil ->
        [
          %{
            title: "No Refund Policy Available",
            content:
              "Refund policy information is not currently available. Please contact the club for cancellation and refund information."
          }
        ]

      policy ->
        if policy.rules && length(policy.rules) > 0 do
          # Format rules with days and percentages
          policy.rules
          |> Enum.map(fn rule ->
            refund_percentage = Decimal.to_float(rule.refund_percentage)

            refund_percentage_str =
              cond do
                refund_percentage == 0 -> "0%"
                refund_percentage == trunc(refund_percentage) -> "#{trunc(refund_percentage)}%"
                true -> "#{:erlang.float_to_binary(refund_percentage, [{:decimals, 1}])}%"
              end

            %{
              title: "#{rule.days_before_checkin} Days Before Check-In",
              content:
                "#{rule.description || "Cancellations made #{rule.days_before_checkin} days or less before check-in will receive a #{refund_percentage_str} refund."}"
            }
          end)
        else
          [
            %{
              title: "Full Refund Available",
              content:
                "Cancellations are eligible for a full refund. Please contact the club for more information."
            }
          ]
        end
    end
  end
end
