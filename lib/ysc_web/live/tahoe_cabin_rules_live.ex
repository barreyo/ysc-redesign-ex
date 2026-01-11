defmodule YscWeb.TahoeCabinRulesLive do
  use YscWeb, :live_view
  use YscNative, :live_view

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

  defp get_categories do
    [
      %{id: "trash", title: "Trash", icon: "trash"},
      %{id: "bears", title: "Bears", icon: "pawprint"},
      %{id: "checkout", title: "Checkout", icon: "door.left.hand.open"},
      %{id: "kitchen", title: "Kitchen", icon: "fork.knife"},
      %{id: "parking", title: "Parking", icon: "car"},
      %{id: "etiquette", title: "Cabin Etiquette", icon: "house"},
      %{id: "what_to_bring", title: "What to Bring", icon: "bag"},
      %{id: "pets", title: "Pets", icon: "pawprint.circle"},
      %{id: "smoking", title: "Smoking", icon: "nosign"},
      %{id: "children", title: "Children", icon: "figure.child"}
    ]
  end

  defp get_rules_data do
    %{
      "trash" => [
        %{
          title: "Bear-Proof Garbage",
          content:
            "Use bear-proof lids on all garbage cans at all times. Secure bear-proof garbage lids before leaving."
        },
        %{
          title: "Disposal",
          content: "Properly dispose of all trash before checkout. Remove all food from the refrigerator."
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
          content: "Checkout is at 11:00 AM. Please ensure you have completed all required cleaning before this time."
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
          content:
            "If you use club bedding, you must wash, dry, and fold it before leaving."
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
end
