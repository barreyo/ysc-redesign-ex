defmodule YscWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At the first glance, this module may seem daunting, but its goal is
  to provide some core building blocks in your application, such as modals,
  tables, and forms. The components are mostly markup and well documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component

  import Flop.Phoenix
  alias Phoenix.LiveView.JS
  import YscWeb.Gettext

  alias Ysc.Events.Event

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>

  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :fullscreen, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="fixed inset-0 transition-opacity bg-zinc-50/90" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex items-center justify-center min-h-full">
          <div class={"w-full #{if @fullscreen == true, do: "w-full", else: "max-w-3xl"} p-4 sm:p-6 lg:py-8"}>
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="relative hidden transition bg-white shadow-lg shadow-zinc-700/10 ring-zinc-700/10 rounded p-14 ring-1"
            >
              <div class="absolute top-6 right-7">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="flex-none rounded hover:bg-zinc-100 p-1 -m-3 opacity-20 hover:opacity-40"
                  aria-label={gettext("close")}
                >
                  <.icon name="hero-x-mark-solid" class="w-6 h-6" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                <%= render_slot(@inner_block) %>
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, default: "flash", doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-2 right-2 w-80 sm:w-96 z-50 rounded-lg p-3 ring-1",
        @kind == :info && "bg-emerald-50 text-emerald-800 ring-emerald-500 fill-cyan-900",
        @kind == :error && "bg-rose-50 text-rose-900 shadow-md ring-rose-500 fill-rose-900"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="w-4 h-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="w-4 h-4" />
        <%= @title %>
      </p>
      <p class="mt-2 text-sm leading-5"><%= msg %></p>
      <button type="button" class="absolute p-2 group top-1 right-1" aria-label={gettext("close")}>
        <.icon name="hero-x-mark-solid" class="w-5 h-5 opacity-40 group-hover:opacity-70" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  def flash_group(assigns) do
    ~H"""
    <.flash kind={:info} title="Success!" flash={@flash} />
    <.flash kind={:error} title="Error!" flash={@flash} />
    <.flash
      id="client-error"
      kind={:error}
      title="We can't find the internet"
      phx-disconnected={show(".phx-client-error #client-error")}
      phx-connected={hide("#client-error")}
      hidden
    >
      Attempting to reconnect <.icon name="hero-arrow-path" class="w-3 h-3 ml-1 animate-spin" />
    </.flash>

    <.flash
      id="server-error"
      kind={:error}
      title="Something went wrong!"
      phx-disconnected={show(".phx-server-error #server-error")}
      phx-connected={hide("#server-error")}
      hidden
    >
      Hang in there while we get back on track
      <.icon name="hero-arrow-path" class="w-3 h-3 ml-1 animate-spin" />
    </.flash>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the datastructure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="mt-10 space-y-8 bg-white">
        <%= render_slot(@inner_block, f) %>
        <div :for={action <- @actions} class="flex items-center justify-between gap-6 mt-2">
          <%= render_slot(action, f) %>
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :color, :string, default: "blue"
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded bg-#{@color}-700 hover:bg-#{@color}-800 py-2 px-3 transition duration-200 ease-in-out disabled:cursor-not-allowed disabled:opacity-80",
        "text-sm font-semibold leading-6 text-zinc-100 active:text-zinc-100/80",
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :subtitle, :string, default: ""
  attr :icon, :string

  attr :growing_field_size, :string, default: "small"

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week checkgroup
               country-select large-radio phone-input date-text text-growing)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox", value: value} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn -> Phoenix.HTML.Form.normalize_value("checkbox", value) end)

    ~H"""
    <div phx-feedback-for={@name}>
      <label class="flex items-center gap-4 text-sm leading-6 text-zinc-600">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-zinc-300 text-zinc-900 focus:ring-0"
          {@rest}
        />
        <%= @label %>
      </label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "radio"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <input
        type="radio"
        id={@id}
        name={@name}
        value={@value}
        checked={@checked}
        class="rounded border-zinc-300 text-zinc-900 focus:ring-0"
        {@rest}
      />
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "large-radio"} = assigns) do
    ~H"""
    <input
      type="radio"
      id={@id}
      name={@name}
      value={@value}
      checked={@checked}
      class="hidden peer"
      {@rest}
      required
    />
    <label
      for={@id}
      class="inline-flex items-center transition duration-150 ease-in-out justify-between w-full p-5 bg-white border rounded-lg cursor-pointer text-zinc-500 border-zinc-200 peer-checked:border-blue-600 peer-checked:text-blue-600 hover:text-zinc-600 hover:bg-zinc-100"
    >
      <div class="flex flex-row">
        <div class="text-center items-center flex mr-4">
          <.icon name={"hero-" <> @icon} class="w-8 h-8" />
        </div>
        <div class="block">
          <div class="w-full font-semibold text-md text-zinc-800"><%= @label %></div>
          <div class="w-full text-sm text-zinc-600"><%= @subtitle %></div>
        </div>
      </div>
    </label>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <select
        id={@id}
        name={@name}
        class="block h-10 min-w-30 mt-2 bg-white border rounded-md shadow-sm border-zinc-300 focus:border-zinc-400 focus:ring-0 sm:text-sm"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value=""><%= @prompt %></option>
        <%= Phoenix.HTML.Form.options_for_select(@options, @value) %>
      </select>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "country-select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <select
        id={@id}
        name={@name}
        class="block w-full mt-2 h-11 bg-white border rounded-md shadow-sm border-zinc-300 focus:border-zinc-400 focus:ring-0 sm:text-sm text-zinc-800"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value=""><%= @prompt %></option>
        <%= Phoenix.HTML.Form.options_for_select(
          Enum.map(LivePhone.Country.list(["US", "SE", "FI", "DK", "NO", "IS"]), fn x ->
            {x.name, x.code}
          end),
          @value
        ) %>
      </select>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-800 focus:ring-0 sm:text-sm sm:leading-6",
          "min-h-[6rem] phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "checkgroup"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name} class="text-sm">
      <.label for={@id}><%= @label %></.label>
      <div class="w-full bg-white rounded text-left cursor-default focus:outline-none focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm">
        <div class="grid grid-cols-1 gap-1 text-sm items-baseline">
          <input type="hidden" name={@name} value="" />
          <div :for={{label, value} <- @options} class="flex items-center">
            <label for={"#{@name}-#{value}"} class="font-medium text-zinc-700 py-1">
              <input
                type="checkbox"
                id={"#{@name}-#{value}"}
                name={@name}
                value={value}
                checked={@value && value in @value}
                class="mr-2 h-4 w-4 rounded border-zinc-300 text-blue-600 focus:ring-blue-400 transition duration-150 ease-in-out"
                {@rest}
              />
              <%= label %>
            </label>
          </div>
        </div>
      </div>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "phone-input"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name} class="phx-no-feedback">
      <.label for={"live_phone-" <> @id}><%= @label %></.label>
      <.live_component
        module={LivePhone}
        id={@id}
        form={assigns[:form]}
        field={@field}
        tabindex={0}
        name={@name}
        preferred={["US", "SE", "FI", "NO", "IS", "DK"]}
        class={[
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
      />
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "date-text"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <input
        type="text"
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value("date", @value)}
        class={[
          "mt-2 block w-full rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        onfocus="(this.type='date')"
        {@rest}
      />
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "text-growing"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        phx-hook="GrowingInput"
        growing-input-size={@growing_field_size}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        {@rest}
      />
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "text-icon"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>

      <div class="relative">
        <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none">
          <%= render_slot(@inner_block) %>
        </div>
        <input
          type="text"
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            "mt-2 block w-full ps-7 rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
            "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
            @errors == [] && "border-zinc-300 focus:border-zinc-400",
            @errors != [] && "border-rose-400 focus:border-rose-400"
          ]}
          {@rest}
        />
      </div>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}><%= @label %></.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "mt-2 block w-full rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :options, :list, doc: "the options for the radio buttons in the fieldset"
  attr :checked_value, :string, doc: "the currently checked value"

  def radio_fieldset(%{field: %Phoenix.HTML.FormField{}} = assigns) do
    ~H"""
    <div phx-feedback-for={@field.name}>
      <ul class="grid w-full gap-6 md:grid-cols-2">
        <li :for={{_, values} <- @options}>
          <.input
            field={@field}
            id={"#{@field.id}_#{values[:option]}"}
            type="large-radio"
            label={String.capitalize(values[:option])}
            value={values[:option]}
            checked={
              @checked_value == values[:option] || @field.value == String.to_atom(values[:option])
            }
            subtitle={values[:subtitle]}
            icon={values[:icon]}
          />
        </li>
      </ul>
    </div>
    """
  end

  @doc """
  Generate a checkbox group for multi-select.
  """
  attr :id, :any
  attr :name, :any
  attr :label, :string, default: nil

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :rest, :global, include: ~w(disabled form readonly)
  attr :class, :string, default: nil

  def checkgroup(assigns) do
    new_assigns =
      assigns
      |> assign(:multiple, true)
      |> assign(:type, "checkgroup")

    input(new_assigns)
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-zinc-800">
      <%= render_slot(@inner_block) %>
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="flex gap-3 mt-3 text-sm leading-6 text-rose-600 phx-no-feedback:hidden">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      <%= render_slot(@inner_block) %>
    </p>
    """
  end

  @min_date Date.utc_today() |> Date.add(-365)

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)

  attr(:start_date_field, :any,
    doc: "a %Phoenix.HTML.Form{}/field name tuple, for example: @form[:start_date]"
  )

  attr(:end_date_field, :any,
    doc: "a %Phoenix.HTML.Form{}/field name tuple, for example: @form[:end_date]"
  )

  attr(:required, :boolean, default: false)
  attr(:readonly, :boolean, default: false)
  attr(:min, :any, default: @min_date, doc: "the earliest date that can be set")
  attr(:errors, :list, default: [])
  attr(:form, :any)

  def date_range_picker(assigns) do
    ~H"""
    <.live_component
      module={YscWeb.Components.DateRangePicker}
      label={@label}
      id={@id}
      form={@form}
      start_date_field={@start_date_field}
      end_date_field={@end_date_field}
      required={@required}
      readonly={@readonly}
      is_range?
      min={@min}
    />
    <div phx-feedback-for={@start_date_field.name}>
      <.error :for={msg <- @start_date_field.errors}><%= format_form_error(msg) %></.error>
    </div>
    <div phx-feedback-for={@end_date_field.name}>
      <.error :for={msg <- @end_date_field.errors}><%= format_form_error(msg) %></.error>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)

  attr(:start_date_field, :any,
    doc: "a %Phoenix.HTML.Form{}/field name tuple, for example: @form[:start_date]"
  )

  attr(:required, :boolean, default: false)
  attr(:readonly, :boolean, default: false)
  attr(:min, :any, default: @min_date, doc: "the earliest date that can be set")
  attr(:errors, :list, default: [])
  attr(:form, :any)

  def date_picker(assigns) do
    ~H"""
    <.live_component
      module={YscWeb.Components.DateRangePicker}
      label={@label}
      id={@id}
      form={@form}
      start_date_field={@start_date_field}
      required={@required}
      readonly={@readonly}
      is_range?={false}
      min={@min}
    />
    <div phx-feedback-for={@start_date_field.name}>
      <.error :for={msg <- @start_date_field.form.errors}><%= format_form_error(msg) %></.error>
    </div>
    """
  end

  defp format_form_error({_key, {msg, _type}}), do: msg
  defp format_form_error({msg, _type}), do: msg

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800">
          <%= render_slot(@inner_block) %>
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600">
          <%= render_slot(@subtitle) %>
        </p>
      </div>
      <div class="flex-none"><%= render_slot(@actions) %></div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="px-4 overflow-y-auto sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm leading-6 text-left text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pb-4 pr-6 font-normal"><%= col[:label] %></th>
            <th class="relative p-0 pb-4"><span class="sr-only"><%= gettext("Actions") %></span></th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative text-sm leading-6 border-t divide-y divide-zinc-100 border-zinc-200 text-zinc-700"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-zinc-50">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute right-0 -inset-y-px -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  <%= render_slot(col, @row_item.(row)) %>
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative p-0 w-14">
              <div class="relative py-4 text-sm font-medium text-right whitespace-nowrap">
                <span class="absolute left-0 -inset-y-px -right-4 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  <%= render_slot(action, @row_item.(row)) %>
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title"><%= @post.title %></:item>
        <:item title="Views"><%= @post.views %></:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="flex-none w-1/4 text-zinc-500"><%= item.title %></dt>
          <dd class="text-zinc-700"><%= render_slot(item) %></dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div>
      <.link
        navigate={@navigate}
        class="text-sm font-semibold leading-6 text-zinc-600 hover:text-zinc-800 rounded hover:bg-zinc-100 p-2"
      >
        <.icon name="hero-arrow-left-solid" class="w-3 h-3 -mt-0.5" />
        <%= render_slot(@inner_block) %>
      </.link>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from your `assets/vendor/heroicons` directory and bundled
  within your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="w-3 h-3 ml-1 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  attr :country, :string, required: true
  attr :class, :string, default: nil

  def flag(%{country: "fi-" <> _} = assigns) do
    ~H"""
    <span class={["fi", @country, @class]} />
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :right, :boolean, default: false
  attr :mobile, :boolean, default: false
  attr :wide, :boolean, default: false
  slot :button_block, required: true
  slot :inner_block, required: true

  def dropdown(assigns) do
    ~H"""
    <div class="relative">
      <button
        type="button"
        id={"#{@id}Link"}
        data-dropdown-toggle={@id}
        class={"flex items-center justify-between w-full px-3 py-2 font-bold transition duration-200 ease-in-out rounded lg:w-auto #{@class}"}
        phx-click={show_dropdown("##{@id}")}
      >
        <%= render_slot(@button_block) %>
      </button>
      <!-- Dropdown menu -->
      <div
        id={@id}
        class={[
          "z-10 hidden mt-1 font-normal bg-white divide-y rounded divide-zinc-100 shadow w-52 wide:w-72",
          @right && "right-0",
          !@right && "left-0",
          @mobile && "block lg:absolute shadow-none lg:shadow",
          !@mobile && "absolute shadow",
          @wide && "wide"
        ]}
        phx-click-away={hide_dropdown("##{@id}")}
      >
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  attr :user_id, :string, required: true
  attr :email, :string, required: true
  attr :first_name, :string, required: true
  attr :last_name, :string, required: true
  attr :most_connected_country, :string, required: true
  slot :inner_block, required: true

  def user_avatar(assigns) do
    ~H"""
    <div class="relative">
      <button
        data-dropdown-toggle="avatar-menu"
        id="avatar-menu-link"
        class="flex flex-row rounded hover:bg-zinc-100 pl-3"
        phx-click={show_dropdown("#avatar-menu")}
      >
        <.user_card
          email={@email}
          user_id={@user_id}
          most_connected_country={@most_connected_country}
          first_name={@first_name}
          last_name={@last_name}
          right={true}
          show_subtitle={false}
        />
      </button>
      <!-- Dropdown menu -->
      <div
        id="avatar-menu"
        class="absolute z-10 hidden w-60 mt-0 font-normal bg-white divide-y rounded shadow divide-zinc-100 right-4 mt-1"
        phx-click-away={hide_dropdown("#avatar-menu")}
      >
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  attr :active_page, :string
  attr :email, :string
  attr :first_name, :string
  attr :last_name, :string
  attr :user_id, :string
  attr :most_connected_country, :string
  slot :inner_block, required: true

  def side_menu(assigns) do
    ~H"""
    <button
      class="inline-flex items-center mb-2 p-2 mt-2 ms-3 text-sm text-zinc-500 rounded sm:hidden hover:bg-zinc-100 focus:outline-none focus:ring-2 focus:ring-zinc-200"
      aria-controls="sidebar navigation"
      type="button"
      phx-click={show_sidebar("#admin-navigation")}
    >
      <span class="sr-only">Open sidebar navigation</span>
      <.icon name="hero-bars-3" class="w-8 h-8" />
    </button>

    <aside
      id="admin-navigation"
      class="fixed top-0 left-0 z-40 w-72 h-screen transition-transform -translate-x-full sm:translate-x-0"
      aria-label="Sidebar"
      phx-click-away={hide_sidebar("#admin-navigation")}
    >
      <div class="h-full px-5 py-8 overflow-y-auto bg-zinc-100 relative">
        <.link navigate="/" class="items-center group ps-2.5 mb-5 inline-block">
          <.ysc_logo class="h-12 sm:h-16 me-3" />
          <span class="block group-hover:underline text-sm font-bold text-zinc-600 py-4">
            Go to site <.icon name="hero-arrow-right" class="h-4 w-4" />
          </span>
        </.link>

        <ul class="space-y-2 leading-6 mt-4 font-medium">
          <li>
            <.link
              navigate="/admin"
              class={[
                "flex items-center px-3 py-4 text-zinc-600 rounded hover:bg-zinc-200 hover:text-zinc-800 group",
                @active_page == :dashboard && "bg-zinc-200 text-zinc-800"
              ]}
              aria-current={@active_page == :dashboard}
            >
              <.icon
                name="hero-chart-pie"
                class={[
                  "w-5 h-5 text-zinc-500 transition duration-75 group-hover:text-zinc-800",
                  @active_page == :dashboard && "text-zinc-800"
                ]}
              />
              <span class="ms-3">Overview</span>
            </.link>
          </li>

          <li>
            <.link
              navigate="/admin/posts"
              class={[
                "flex items-center px-3 py-4 text-zinc-600 rounded hover:bg-zinc-200 hover:text-zinc-800 group",
                @active_page == :news && "bg-zinc-200 text-zinc-800"
              ]}
              aria-current={@active_page == :news}
            >
              <.icon
                name="hero-document-text"
                class={[
                  "w-5 h-5 text-zinc-500 transition duration-75 group-hover:text-zinc-800",
                  @active_page == :news && "text-zinc-800"
                ]}
              />
              <span class="ms-3">Posts</span>
            </.link>
          </li>

          <li>
            <.link
              navigate="/admin/events"
              class={[
                "flex items-center px-3 py-4 text-zinc-600 rounded hover:bg-zinc-200 hover:text-zinc-800 group",
                @active_page == :events && "bg-zinc-200 text-zinc-800"
              ]}
              aria-current={@active_page == :events}
            >
              <.icon
                name="hero-calendar"
                class={[
                  "w-5 h-5 text-zinc-500 transition duration-75 group-hover:text-zinc-800",
                  @active_page == :events && "text-zinc-800"
                ]}
              />
              <span class="ms-3">Events</span>
            </.link>
          </li>

          <li>
            <.link
              navigate="/admin/bookings"
              class={[
                "flex items-center px-3 py-4 text-zinc-600 rounded hover:bg-zinc-200 hover:text-zinc-800 group",
                @active_page == :bookings && "bg-zinc-200 text-zinc-800"
              ]}
              aria-current={@active_page == :bookings}
            >
              <.icon
                name="hero-home"
                class={[
                  "w-5 h-5 text-zinc-500 transition duration-75 group-hover:text-zinc-800",
                  @active_page == :bookings && "text-zinc-800"
                ]}
              />
              <span class="ms-3">Bookings</span>
            </.link>
          </li>

          <li>
            <.link
              navigate="/admin/users"
              class={[
                "flex items-center px-3 py-4 text-zinc-600 rounded hover:bg-zinc-200 hover:text-zinc-800 group",
                @active_page == :members && "bg-zinc-200 text-zinc-800"
              ]}
              aria-current={@active_page == :members}
            >
              <.icon
                name="hero-users"
                class={[
                  "w-5 h-5 text-zinc-500 transition duration-75 group-hover:text-zinc-800",
                  @active_page == :members && "text-zinc-800"
                ]}
              />
              <span class="ms-3">Users</span>
            </.link>
          </li>

          <li>
            <.link
              navigate="/admin/money"
              class={[
                "flex items-center px-3 py-4 text-zinc-600 rounded hover:bg-zinc-200 hover:text-zinc-800 group",
                @active_page == :money && "bg-zinc-200 text-zinc-800"
              ]}
              aria-current={@active_page == :money}
            >
              <.icon
                name="hero-wallet"
                class={[
                  "w-5 h-5 text-zinc-500 transition duration-75 group-hover:text-zinc-800",
                  @active_page == :money && "text-zinc-800"
                ]}
              />
              <span class="ms-3">Money</span>
            </.link>
          </li>

          <li>
            <.link
              navigate="/admin/media"
              class={[
                "flex items-center px-3 py-4 text-zinc-600 rounded hover:bg-zinc-200 hover:text-zinc-800 group",
                @active_page == :media && "bg-zinc-200 text-zinc-800"
              ]}
              aria-current={@active_page == :media}
            >
              <.icon
                name="hero-photo"
                class={[
                  "w-5 h-5 text-zinc-500 transition duration-75 group-hover:text-zinc-800",
                  @active_page == :media && "text-zinc-800"
                ]}
              />
              <span class="ms-3">Media</span>
            </.link>
          </li>

          <li>
            <.link
              navigate="/admin/settings"
              class={[
                "flex items-center px-3 py-4 text-zinc-600 rounded hover:bg-zinc-200 hover:text-zinc-800 group",
                @active_page == :admin_settings && "bg-zinc-200 text-zinc-800"
              ]}
              aria-current={@active_page == :admin_settings}
            >
              <.icon
                name="hero-cog-6-tooth"
                class={[
                  "w-5 h-5 text-zinc-500 transition duration-75 group-hover:text-zinc-800",
                  @active_page == :admin_settings && "text-zinc-800"
                ]}
              />
              <span class="ms-3">Settings</span>
            </.link>
          </li>
        </ul>

        <div class="absolute inset-x-0 bottom-0 px-4 py-4 border-t border-1 border-zinc-200 bg-zinc-100">
          <.user_card
            email={@email}
            user_id={@user_id}
            most_connected_country={@most_connected_country}
            first_name={@first_name}
            last_name={@last_name}
          />
        </div>
      </div>
    </aside>

    <main class="px-6 md:px-10 sm:ml-72">
      <%= render_slot(@inner_block) %>
    </main>

    <div id="drawer-backdrop" class="hidden bg-zinc-900/50 fixed inset-0 z-30" drawer-backdrop="">
    </div>
    """
  end

  @board_position_to_title_lookup %{
    president: "President",
    vice_president: "Vice President",
    secretary: "Secretary",
    treasurer: "Treasurer",
    clear_lake_cabin_master: "Clear Lake Cabin Master",
    tahoe_cabin_master: "Tahoe Cabin Master",
    event_director: "Event Director",
    member_outreach: "Member Outreach & Events",
    membership_director: "Membership Director"
  }

  attr :email, :string, required: true
  attr :title, :string, required: false, default: nil
  attr :user_id, :string, required: true
  attr :most_connected_country, :string, required: true
  attr :first_name, :string, required: true
  attr :last_name, :string, required: true
  attr :right, :boolean, default: false
  attr :show_subtitle, :boolean, default: true
  attr :class, :string, default: ""

  def user_card(assigns) do
    subtitle =
      if assigns[:title] != nil do
        "YSC #{Map.get(@board_position_to_title_lookup,
        assigns[:title],
        String.capitalize("#{assigns[:title]}"))}"
      else
        String.downcase(assigns[:email])
      end

    new_assigns = assign(assigns, :subtitle, subtitle)

    ~H"""
    <div class={"flex items-center whitespace-nowrap h-10 #{@class}"}>
      <.user_avatar_image
        email={@email}
        user_id={@user_id}
        country={@most_connected_country}
        class={[
          "w-10 rounded-full",
          @right && "order-2"
        ]}
      />
      <div class={[
        @right && "order-1 pe-3",
        !@right && "ps-3"
      ]}>
        <div class="text-sm font-semibold text-zinc-800 text-left">
          <%= "#{String.capitalize(@first_name)} #{String.capitalize(@last_name)}" %>
        </div>
        <div :if={@show_subtitle} class="font-normal text-sm text-zinc-500">
          <%= new_assigns[:subtitle] %>
        </div>
      </div>
    </div>
    """
  end

  attr :toggle_id, :string, required: true

  def hamburger_menu(assigns) do
    ~H"""
    <button
      data-collapse-toggle="navbar-sticky"
      type="button"
      class="inline-flex items-center justify-center h-10 p-2 text-sm transition ease-in-out rounded text-zinc-900 lg:hidden hover:bg-zinc-200 focus:outline-none focus:ring-2 focus:ring-zinc-300 duration-400"
      aria-controls="navbar-sticky"
      aria-expanded="false"
      phx-click={toggle_expanded(@toggle_id)}
    >
      <.icon name="hero-bars-3" class="w-5 h-5 fill-inherit" />
      <span class="ml-2 font-bold text-zinc-900 hover:text-black">
        Menu
      </span>
    </button>
    """
  end

  attr :type, :string, default: "default"
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[
      "text-xs font-medium me-2 px-2 py-1 rounded text-left #{@class}",
      @type == "sky" && "bg-sky-100 text-sky-800",
      @type == "green" && "bg-green-100 text-green-800",
      @type == "yellow" && "bg-yellow-100 text-yellow-800",
      @type == "red" && "bg-red-100 text-red-800",
      @type == "dark" && "bg-zinc-100 text-zinc-800",
      @type == "default" && "bg-blue-100 text-blue-800"
    ]}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  attr :class, :string, default: nil
  attr :tooltip_text, :string, required: true
  slot :inner_block, required: true

  @spec tooltip(map()) :: Phoenix.LiveView.Rendered.t()
  def tooltip(assigns) do
    ~H"""
    <div>
      <div class="group relative">
        <%= render_slot(@inner_block) %>
        <span
          role="tooltip"
          class="absolute transition-opacity mt-10 top-0 left-0 duration-200 opacity-0 z-50 text-xs font-medium text-zinc-100 bg-zinc-900 rounded-lg shadow-sm px-3 py-2 inline-block text-center rounded tooltip group-hover:opacity-100"
        >
          <%= @tooltip_text %>
        </span>
      </div>
    </div>
    """
  end

  attr :event, :any, required: true

  def event_badge(assigns) do
    assigns = assign(assigns, :event, assigns.event)

    ~H"""
    <.badge :if={event_badge_style(@event) != nil} class="text-xs font-medium">
      <%= event_badge_text(@event) %>
    </.badge>
    """
  end

  defp event_badge_style(%Event{state: :cancelled}), do: "dark"
  defp event_badge_style(_), do: nil

  defp event_badge_text(%Event{state: :cancelled}), do: "Cancelled"
  defp event_badge_text(_), do: nil

  attr :active_step, :integer, required: true
  attr :steps, :list, default: []

  @spec stepper(map()) :: Phoenix.LiveView.Rendered.t()
  def stepper(assigns) do
    assigns =
      assigns
      |> assign(:stepper_max_length, length(assigns.steps))

    ~H"""
    <ol class="flex items-center w-full px-4 py-3 space-x-2 text-sm font-medium text-center border rounded text-zinc-400 border-zinc-100 sm:text-base sm:p-4 sm:space-x-4 rtl:space-x-reverse">
      <%= for {val, idx} <- Enum.with_index(@steps) do %>
        <li :if={idx != @active_step}>
          <button
            phx-click="set-step"
            phx-value-step={idx}
            class="flex items-center leading-6 text-sm"
          >
            <span class="flex items-center text-zinc-400 justify-center w-6 h-6 text-xs font-bold border rounded me-2 shrink-0 border-zinc-400">
              <%= idx + 1 %>
            </span>
            <%= val %>
            <.icon
              :if={idx + 1 < assigns[:stepper_max_length]}
              name="hero-chevron-right"
              class="w-5 h-5 ml-2"
            />
          </button>
        </li>
        <li :if={idx == @active_step} class="flex items-center leading-6 text-blue-800 text-sm">
          <span class="flex items-center text-zinc-100 justify-center w-6 h-6 text-xs font-bold bg-blue-600 border border-blue-600 rounded me-2 shrink-0">
            <%= idx + 1 %>
          </span>
          <%= val %>
          <.icon
            :if={idx + 1 < assigns[:stepper_max_length]}
            name="hero-chevron-right"
            class="w-5 h-5 ml-2"
          />
        </li>
      <% end %>
    </ol>
    """
  end

  attr :class, :string, default: nil

  def ysc_logo(assigns) do
    ~H"""
    <img class={@class} src="/images/ysc_logo.png" alt="The Young Scandinavian Club Logo" />
    """
  end

  attr :viking, :integer, default: 4
  attr :title, :string, default: "Looks like this page is empty"
  attr :suggestion, :string, default: nil

  def empty_viking_state(assigns) do
    ~H"""
    <div class="text-center justify-center items-center w-full">
      <img
        class={[
          "w-60 mx-auto",
          Enum.member?([2, 4], @viking) && "rounded-full"
        ]}
        src={"/images/vikings/small/viking_#{@viking}.png"}
        alt="Looks like this page is empty"
      />
      <.header class="pt-8">
        <%= @title %>
        <:subtitle><%= @suggestion %></:subtitle>
      </.header>
    </div>
    """
  end

  attr :class, :string, default: nil

  def spinner(assigns) do
    ~H"""
    <div role="status">
      <svg
        aria-hidden="true"
        class={"text-zinc-200 animate-spin fill-blue-600 #{@class}"}
        viewBox="0 0 100 101"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <path
          d="M100 50.5908C100 78.2051 77.6142 100.591 50 100.591C22.3858 100.591 0 78.2051 0 50.5908C0 22.9766 22.3858 0.59082 50 0.59082C77.6142 0.59082 100 22.9766 100 50.5908ZM9.08144 50.5908C9.08144 73.1895 27.4013 91.5094 50 91.5094C72.5987 91.5094 90.9186 73.1895 90.9186 50.5908C90.9186 27.9921 72.5987 9.67226 50 9.67226C27.4013 9.67226 9.08144 27.9921 9.08144 50.5908Z"
          fill="currentColor"
        />
        <path
          d="M93.9676 39.0409C96.393 38.4038 97.8624 35.9116 97.0079 33.5539C95.2932 28.8227 92.871 24.3692 89.8167 20.348C85.8452 15.1192 80.8826 10.7238 75.2124 7.41289C69.5422 4.10194 63.2754 1.94025 56.7698 1.05124C51.7666 0.367541 46.6976 0.446843 41.7345 1.27873C39.2613 1.69328 37.813 4.19778 38.4501 6.62326C39.0873 9.04874 41.5694 10.4717 44.0505 10.1071C47.8511 9.54855 51.7191 9.52689 55.5402 10.0491C60.8642 10.7766 65.9928 12.5457 70.6331 15.2552C75.2735 17.9648 79.3347 21.5619 82.5849 25.841C84.9175 28.9121 86.7997 32.2913 88.1811 35.8758C89.083 38.2158 91.5421 39.6781 93.9676 39.0409Z"
          fill="currentFill"
        />
      </svg>
      <span class="sr-only">Loading...</span>
    </div>
    """
  end

  attr :progress, :integer, required: true

  @spec progress_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def progress_bar(assigns) do
    ~H"""
    <div class="w-full bg-zinc-200 rounded h-2">
      <div
        class="animate-pulse transition duration-100 ease-in-out bg-blue-600 h-2 rounded "
        style={"width: #{@progress}%"}
      >
      </div>
    </div>
    """
  end

  attr :fields, :list, required: true
  attr :meta, Flop.Meta, required: true
  attr :id, :string, default: nil
  attr :on_change, :string, default: "update-filter"
  attr :target, :string, default: nil

  @spec filter_form(map()) :: Phoenix.LiveView.Rendered.t()
  def filter_form(%{meta: meta} = assigns) do
    assigns =
      assign(assigns, form: Phoenix.Component.to_form(meta), meta: nil)

    ~H"""
    <.form for={@form} id={@id} phx-target={@target} phx-change={@on_change} phx-submit={@on_change}>
      <.filter_fields :let={i} form={@form} fields={@fields}>
        <.input field={i.field} label={i.label} type={i.type} phx-debounce={120} {i.rest} />
      </.filter_fields>
    </.form>
    """
  end

  @default_images %{
    "DK" => %{
      0 => "/images/default_avatars/denmark_flag.png",
      1 => "/images/default_avatars/denmark_houses.png"
    },
    "FI" => %{
      0 => "/images/default_avatars/finland_flag.png",
      1 => "/images/default_avatars/finland_house.png"
    },
    "IS" => %{
      0 => "/images/default_avatars/iceland_flag.png",
      1 => "/images/default_avatars/iceland_landscape.png"
    },
    "NO" => %{
      0 => "/images/default_avatars/norway_flag.png",
      1 => "/images/default_avatars/norway_fjord.png"
    },
    "SE" => %{
      0 => "/images/default_avatars/sweden_flag.png",
      1 => "/images/default_avatars/sweden_houses.png"
    }
  }

  attr :email, :string, required: true
  attr :user_id, :string, required: true
  attr :country, :string, required: true
  attr :class, :string, default: ""

  def user_avatar_image(assigns) do
    cleaned_email = String.downcase(assigns[:email]) |> String.trim()
    email_hash = :crypto.hash(:sha256, cleaned_email) |> Base.encode16(case: :lower)

    image_id =
      assigns[:user_id] |> String.replace(~r/[^\d]/, "") |> String.to_integer() |> rem(2)

    image_path = Map.get(Map.get(@default_images, assigns[:country]), image_id)

    assigns =
      assigns
      |> assign(:full_path, full_path(email_hash, image_path))

    ~H"""
    <img class={@class} src={@full_path} loading="lazy" />
    """
  end

  defp full_path(email_hash, image_path) do
    if Application.get_env(:ysc, :dev_routes, false) == true do
      image_path
    else
      "https://gravatar.com/avatar/#{@email_hash}?d=#{@image_path}"
    end
  end

  attr :color, :string, default: "blue"
  slot :inner_block, required: true

  def alert_box(assigns) do
    ~H"""
    <div class={"flex p-4 mb-4 text-sm text-#{@color}-800 rounded bg-#{@color}-50"} role="alert">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :class, :string, default: ""
  slot :inner_block, required: true

  def phone_mockup(assigns) do
    ~H"""
    <div class={"relative mx-auto border-zinc-800 bg-zinc-800 border-[14px] rounded-xl h-[600px] w-[300px] shadow-xl #{@class}"}>
      <div class="w-[148px] h-[18px] bg-zinc-800 top-0 rounded-b-[1rem] left-1/2 -translate-x-1/2 absolute">
      </div>
      <div class="h-[32px] w-[3px] bg-zinc-800 absolute -start-[17px] top-[72px] rounded-s-lg"></div>
      <div class="h-[46px] w-[3px] bg-zinc-800 absolute -start-[17px] top-[124px] rounded-s-lg"></div>
      <div class="h-[46px] w-[3px] bg-zinc-800 absolute -start-[17px] top-[178px] rounded-s-lg"></div>
      <div class="h-[64px] w-[3px] bg-zinc-800 absolute -end-[17px] top-[142px] rounded-e-lg"></div>
      <div class="rounded-xl overflow-y-auto w-[272px] h-[572px] bg-white">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  attr :class, :string, default: ""
  slot :inner_block, required: true

  def tablet_mockup(assigns) do
    ~H"""
    <div class={"relative mx-auto border-zinc-800 bg-zinc-800 border-[14px] rounded-[2.5rem] h-[454px] max-w-[341px] md:h-[682px] md:max-w-[512px] #{@class}"}>
      <div class="h-[32px] w-[3px] bg-zinc-800 absolute -start-[17px] top-[72px] rounded-s-lg"></div>
      <div class="h-[46px] w-[3px] bg-zinc-800 absolute -start-[17px] top-[124px] rounded-s-lg"></div>
      <div class="h-[46px] w-[3px] bg-zinc-800 absolute -start-[17px] top-[178px] rounded-s-lg"></div>
      <div class="h-[64px] w-[3px] bg-zinc-800 absolute -end-[17px] top-[142px] rounded-e-lg"></div>
      <div class="rounded-[2rem] overflow-y-auto h-[426px] md:h-[654px] bg-white">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  def editor(assigns) do
    ~H"""
    <div class="w-full prose prose-zinc prose-base">
      <form class="w-full">
        <input id="editor-input" type="hidden" name="content" />
        <trix-editor input="editor-input"></trix-editor>
      </form>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :author, :string, required: true
  attr :author_email, :string, required: true
  attr :author_most_connected, :string, required: true
  attr :author_id, :string, required: true
  attr :date, :any, required: true
  attr :reply, :boolean, default: false
  attr :form, :any, required: true
  attr :post_id, :string, required: true
  attr :reply_to_comment_id, :string, default: nil
  attr :animate, :boolean, default: false

  def comment(assigns) do
    ~H"""
    <article
      id={@id}
      class={[
        "py-4 px-4 text-base rounded",
        @reply && "mb-3 ml-6"
      ]}
      phx-mounted={
        @animate &&
          JS.transition({"transition ease-in duration-500", "opacity-0 ping", "opacity-100"})
      }
    >
      <footer class="flex justify-between items-center">
        <div class="flex items-center">
          <p class="inline-flex items-center mr-3 text-sm text-zinc-900 font-semibold">
            <.user_avatar_image
              email={@author_email}
              user_id={@author_id}
              country={@author_most_connected}
              class="w-6 rounded-full mr-2"
            />
            <%= @author %>
          </p>
          <p class="text-sm text-zinc-600">
            <time
              pubdate
              datetime={Timex.format!(@date, "%Y-%m-%d", :strftime)}
              title={Timex.format!(@date, "%B %e, %Y", :strftime)}
            >
              <%= Timex.format!(@date, "%b %e, %Y", :strftime) %>
            </time>
          </p>
        </div>
      </footer>
      <p class="text-zinc-600">
        <%= @text %>
      </p>
      <div class="flex items-center mt-4 space-x-4">
        <button
          phx-click={JS.show(to: "#reply-to-#{@id}")}
          type="button"
          class="flex items-center text-sm text-zinc-600 hover:text-zinc-800 hover:bg-zinc-100 rounded font-medium px-2 py-1"
        >
          <.icon name="hero-chat-bubble-bottom-center-text" class="mr-1.5 w-4 h-4 mt-0.5" /> Reply
        </button>
      </div>

      <div id={"reply-to-#{@id}"} class="hidden mt-2">
        <.form for={@form} id={"reply-form-#{@post_id}-#{@id}"} phx-submit="save">
          <.input
            field={@form[:text]}
            type="textarea"
            id="comment"
            rows="4"
            class="px-0 w-full text-sm text-zinc-900 border-0 focus:ring-0 focus:outline-none"
            placeholder="Write a nice reply..."
            required
          >
          </.input>
          <input type="hidden" name="comment[post_id]" value={@post_id} />
          <input type="hidden" name="comment[comment_id]" value={@reply_to_comment_id} />
          <button
            type="submit"
            class="inline-flex items-center py-2.5 px-4 text-sm font-bold text-center text-zinc-100 bg-blue-700 rounded focus:ring-4 focus:ring-blue-200 hover:bg-blue-800 mt-4"
            phx-click={
              JS.dispatch("submit", to: "reply-form-#{@post_id}-#{@id}")
              |> JS.hide(to: "#reply-to-#{@id}")
            }
          >
            Post Reply
          </button>
          <button
            type="button"
            phx-click={JS.hide(to: "#reply-to-#{@id}")}
            class="inline-flex items-center py-2.5 px-4 text-sm font-bold text-center text-zinc-600 rounded focus:ring-4 hover:bg-zinc-100 mt-4"
          >
            Cancel
          </button>
        </.form>
      </div>
    </article>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def toggle_expanded(js \\ %JS{}, id) do
    js
    |> JS.remove_class(
      "expanded",
      to: "##{id}.expanded"
    )
    |> JS.add_class(
      "expanded",
      to: "##{id}:not(.expanded)"
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-out duration-100", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-50", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  def show_sidebar(to) do
    JS.remove_class("-translate-x-full", to: to)
    |> JS.add_class("transform-none", to: to)
    |> JS.show(
      to: "#drawer-backdrop",
      transition: {"transition-opacity ease-out duration-75", "opacity-0", "opacity-100"}
    )
    |> JS.set_attribute({"aria-expanded", "true"}, to: to)
  end

  def hide_sidebar(to) do
    JS.remove_class("transform-none", to: to)
    |> JS.add_class("-translate-x-full", to: to)
    |> JS.hide(
      to: "#drawer-backdrop",
      transition: {"transition-opacity ease-in duration-75", "opacity-100", "opacity-0"}
    )
    |> JS.set_attribute({"aria-expanded", "false"}, to: to)
  end

  def show_dropdown(to) do
    JS.show(
      to: to,
      transition:
        {"transition ease-out duration-75", "transform opacity-0 scale-95",
         "transform opacity-100 scale-100"}
    )
    |> JS.set_attribute({"aria-expanded", "true"}, to: to)
  end

  def hide_dropdown(to) do
    JS.hide(
      to: to,
      transition:
        {"transition ease-in duration-75", "transform opacity-100 scale-100",
         "transform opacity-0 scale-95"}
    )
    |> JS.remove_attribute("aria-expanded", to: to)
  end

  @spec translate_error({binary(), keyword() | map()}) :: binary()
  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(YscWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(YscWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  def random_id(prefix) do
    prefix <> "_" <> (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false))
  end
end
