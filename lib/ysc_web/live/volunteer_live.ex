defmodule YscWeb.VolunteerLive do
  use YscWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10 max-w-screen-lg mx-auto px-4">
      <div class="max-w-xl mx-auto lg:mx-0 prose prose-zinc prose-a:text-blue-600 pb-10">
        <h1>Volunteer with the YSC!</h1>

        <p>
          Want to contribute to a vibrant community and help create memorable experiences for others?
        </p>
        <p>
          The YSC thrives on the dedication of our volunteers. Whether you're passionate about event planning, outdoor adventures, or supporting our members, there's a place for you at the YSC. Fill out the form below to join our team and make a lasting impact!
        </p>

        <div>
          <.simple_form for={@form} phx-change="validate" phx-submit="save">
            <.input field={@form[:name]} label="Name (*)" />
            <.input field={@form[:email]} label="Email (*)" />

            <div>
              <p class="font-semibold">
                How would you like to volunteer with the YSC? Select all that apply.
              </p>

              <div class="space-y-1">
                <.input field={@form[:interest_events]} type="checkbox" label="Events/Parties" />
                <.input field={@form[:interest_activities]} type="checkbox" label="Activities" />
                <.input field={@form[:interest_clear_lake]} type="checkbox" label="Clear Lake" />
                <.input field={@form[:interest_tahoe]} type="checkbox" label="Tahoe" />
                <.input field={@form[:interest_marketing]} type="checkbox" label="Marketing" />
                <.input field={@form[:interest_website]} type="checkbox" label="Website" />
              </div>
            </div>

            <div :if={!@logged_in?} class="w-full flex">
              <Turnstile.widget theme="light" />
            </div>

            <.button :if={!@submitted} type="submit">Submit</.button>
            <div :if={@submitted} clas="items-center">
              <.icon name="hero-check-circle" class="text-green-600 w-6 h-6 -mt-1 me-1" />
              <span class="text-zinc-600">
                Submitted! Thank you for your interest in volunteering!
              </span>
            </div>
          </.simple_form>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    remote_ip = get_connect_info(socket, :peer_data).address
    current_user = socket.assigns[:current_user]

    params = starting_params(current_user)
    changeset = Ysc.Forms.Volunteer.changeset(%Ysc.Forms.Volunteer{}, params)

    {:ok,
     socket
     |> assign(:page_title, "Volunteer")
     |> assign(:logged_in?, current_user != nil)
     |> assign(:remote_ip, remote_ip)
     |> assign(:submitted, false)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"volunteer" => volunteer_params}, socket) do
    params = add_user_id(volunteer_params, socket.assigns[:current_user])
    changeset = Ysc.Forms.Volunteer.changeset(%Ysc.Forms.Volunteer{}, params)
    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"volunteer" => volunteer_params} = values, socket) do
    params = add_user_id(volunteer_params, socket.assigns[:current_user])
    changeset = Ysc.Forms.Volunteer.changeset(%Ysc.Forms.Volunteer{}, params)

    if !socket.assigns.logged_in? do
      case Turnstile.verify(values, socket.assigns.remote_ip) do
        {:ok, _} ->
          case Ysc.Forms.create_volunteer(changeset) do
            {:ok, _volunteer} ->
              {:noreply,
               assign(socket, submitted: true)
               |> put_flash(:info, "Thank you for your interest in volunteering with the YSC!")}

            {:error, changeset} ->
              {:noreply, assign_form(socket, changeset)}
          end

        {:error, _} ->
          socket =
            socket
            |> put_flash(:error, "Please try submitting again")
            |> Turnstile.refresh()

          {:noreply, assign_form(socket, changeset)}
      end
    else
      case Ysc.Forms.create_volunteer(changeset) do
        {:ok, _volunteer} ->
          {:noreply,
           assign(socket, submitted: true)
           |> put_flash(:info, "Thank you for your interest in volunteering with the YSC!")}

        {:error, changeset} ->
          {:noreply, assign_form(socket, changeset)}
      end
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "volunteer")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp starting_params(nil) do
    %{}
  end

  defp starting_params(user) do
    %{
      name: "#{user.first_name} #{user.last_name}",
      email: user.email,
      user_id: user.id
    }
  end

  defp add_user_id(params, nil), do: params
  defp add_user_id(params, user), do: Map.put(params, "user_id", user.id)
end
