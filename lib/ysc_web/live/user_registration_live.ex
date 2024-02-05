defmodule YscWeb.UserRegistrationLive do
  alias Ysc.Accounts.SignupApplication
  use YscWeb, :live_view

  alias Ysc.Accounts
  alias Ysc.Accounts.User

  def render(assigns) do
    ~H"""
    <div class="w-full">
      <.stepper active_step={0} steps={["Basics", "About you", "Questions"]} />
    </div>
    <div id="registration-form" class="max-w-lg px-2 py-8">
      <.header class="text-left">
        Apply for membership
        <:subtitle>
          Already a member?
          <.link navigate={~p"/users/log_in"} class="font-semibold text-brand hover:underline">
            Sign in
          </.link>
          to your account now.
        </:subtitle>
      </.header>

      <p class="mt-2 mb-6 text-sm leading-6 text-zinc-600">
        Filling out the application only takes a few minutes. We'll review your application and get back to you as soon as possible!
      </p>

      <.form
        :let={f}
        for={@form}
        id="registration_form"
        phx-submit="save"
        phx-change="validate"
        phx-trigger-action={@trigger_submit}
        action={~p"/users/log_in?_action=registered"}
        method="post"
      >
        <div class="space-y-4">
          <.error :if={@check_errors}>
            Oops, something went wrong! Please check the errors below.
          </.error>

          <div class="py-4">
            <!-- TODO: Label instead of <p> -->
            <p class="mb-4 text-sm font-semibold leading-6 text-zinc-800">
              What type of membership are you applying for?
            </p>
            <ul class="grid w-full gap-6 md:grid-cols-2">
              <li>
                <input
                  type="radio"
                  id="hosting-small"
                  name="hosting"
                  value="hosting-small"
                  class="hidden peer"
                  required
                />
                <label
                  for="hosting-small"
                  class="inline-flex items-center justify-between w-full p-5 bg-white border rounded-lg cursor-pointer text-zinc-500 border-zinc-200 peer-checked:border-blue-800 peer-checked:text-blue-800 hover:text-zinc-600 hover:bg-zinc-100"
                >
                  <div class="block">
                    <div class="w-full font-semibold text-md text-zinc-800">Single</div>
                    <div class="w-full text-sm text-zinc-600">Good for small websites</div>
                  </div>
                </label>
              </li>
              <li>
                <input
                  type="radio"
                  id="hosting-big"
                  name="hosting"
                  value="hosting-big"
                  class="hidden peer"
                />
                <label
                  for="hosting-big"
                  class="inline-flex items-center justify-between w-full p-5 bg-white border rounded-lg cursor-pointer text-zinc-500 border-zinc-200 peer-checked:border-blue-800 peer-checked:text-blue-800 hover:text-zinc-600 hover:bg-zinc-100"
                >
                  <div class="block">
                    <div class="w-full font-semibold text-md text-zinc-800">Family</div>
                    <div class="w-full text-sm text-zinc-600">Good for large websites</div>
                  </div>
                </label>
              </li>
            </ul>
          </div>

          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            placeholder="example@ysc.org"
            required
          />
          <.input field={@form[:password]} type="password" label="Password" required />

          <.input field={@form[:first_name]} label="First Name" required />
          <.input field={@form[:last_name]} label="Last Name" required />

          <.inputs_for :let={rf} field={f[:registration_form]}>
            <fieldset>
              <.input
                id="membership_type_single"
                type="radio"
                value="single"
                label="Single"
                field={rf[:membership_type]}
                checked={rf[:registration_form] == "single"}
              />
              <.input
                id="membership_type_family"
                type="radio"
                value="family"
                label="Family"
                field={rf[:membership_type]}
                checked={rf[:registration_form] == "family"}
              />
            </fieldset>
          </.inputs_for>

          <.button phx-disable-with="Submitting application..." class="w-full">
            Submit application
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    application_changeset = SignupApplication.application_changeset(%SignupApplication{}, %{})

    changeset =
      Accounts.change_user_registration(%User{
        registration_form: application_changeset
      })

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false)
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @spec handle_event(<<_::32, _::_*32>>, map(), any()) :: {:noreply, any()}
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/users/confirm/#{&1}")
          )

        changeset = Accounts.change_user_registration(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    application_changeset =
      SignupApplication.application_changeset(
        %SignupApplication{},
        user_params["registration_form"]
      )

    changeset =
      Accounts.change_user_registration(
        %User{registration_form: application_changeset},
        user_params
      )

    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
