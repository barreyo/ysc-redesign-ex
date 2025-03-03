defmodule YscWeb.ConductViolationReportLive do
  use YscWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="py-8 lg:py-10 max-w-screen-lg mx-auto px-4">
      <div class="max-w-xl mx-auto lg:mx-0 prose prose-zinc prose-a:text-blue-600 pb-10">
        <h1>Report Conduct Violations</h1>

        <p>
          Please reference part, or all, of the YSC Code of Conduct when filing a formal violation. When submitted, you will immediately receive a confirmation e-mail. The YSC board will review the violation and determine the appropriate set of actions.
        </p>

        <p>
          <.link
            navigate={~p"/code-of-conduct"}
            class="text-blue-600 hover:text-blue-700 transition ease-in-out"
          >
            YSC Code of Conduct
          </.link>
        </p>

        <div>
          <.simple_form for={@form} phx-change="validate" phx-submit="save">
            <.input field={@form[:first_name]} label="First Name*" />
            <.input field={@form[:last_name]} label="Last Name*" />
            <.input field={@form[:email]} label="Email*" />
            <.input field={@form[:phone]} label="Phone Number*" />

            <.input type="textarea" field={@form[:summary]} label="Violation Summary*" />

            <div :if={!@logged_in?} class="w-full flex">
              <Turnstile.widget theme="light" />
            </div>

            <.button :if={!@submitted} type="submit">Submit Report</.button>
            <div :if={@submitted} clas="items-center">
              <.icon name="hero-check-circle" class="text-green-600 w-6 h-6 -mt-1 me-1" />
              <span class="text-zinc-600">
                Report has been submitted. We have sent you a confirmation email.
              </span>
              <p class="text-zinc-600">The board will review your report as soon as possible.</p>
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
     |> assign(:page_title, "Report Conduct Violation")
     |> assign(:logged_in?, current_user != nil)
     |> assign(:remote_ip, remote_ip)
     |> assign(:submitted, false)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"conduct_form" => volunteer_params}, socket) do
    changeset =
      Ysc.Forms.ConductViolationReport.changeset(
        %Ysc.Forms.ConductViolationReport{},
        volunteer_params
      )

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"conduct_form" => form_values} = values, socket) do
    changeset =
      Ysc.Forms.ConductViolationReport.changeset(
        %Ysc.Forms.ConductViolationReport{},
        form_values
      )

    if !socket.assigns.logged_in? do
      case Turnstile.verify(values, socket.assigns.remote_ip) do
        {:ok, _} ->
          case Ysc.Forms.create_conduct_violation_report(changeset) do
            {:ok, _volunteer} ->
              {:noreply,
               assign(socket, submitted: true)
               |> put_flash(:info, "Your report has been submitted")}

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
           |> put_flash(:info, "Your report has been submitted")}

        {:error, changeset} ->
          {:noreply, assign_form(socket, changeset)}
      end
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "conduct_form")

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
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      phone: user.phone_number
    }
  end
end
