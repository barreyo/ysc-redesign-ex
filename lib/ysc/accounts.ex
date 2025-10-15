defmodule Ysc.Accounts do
  @moduledoc """
  The Accounts context.
  """
  @behaviour Ysc.Accounts.Behaviour

  import Ecto.Query, warn: false

  alias Ysc.Accounts.UserEvent
  alias Ysc.Accounts.SignupApplicationEvent
  alias YscWeb.Authorization.Policy
  alias Ysc.Accounts.SignupApplication
  alias Ysc.Repo

  alias Ysc.Accounts.{User, UserToken, UserNotifier, AuthService}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @spec get_user_by_email_and_password(binary(), binary()) :: any()
  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id, preloads \\ []) do
    Repo.get!(User, id) |> Repo.preload(preloads)
  end

  def get_user_from_stripe_id(stripe_id) do
    Repo.get_by(User, stripe_id: stripe_id)
  end

  def get_signup_application_from_user_id!(id, current_user, preloads \\ []) do
    with :ok <- Policy.authorize(:signup_application_read, current_user, %{user_id: id}) do
      Repo.get_by!(SignupApplication, user_id: id)
      |> Repo.preload(preloads)
    end
  end

  ## User registration

  @spec register_user(
          :invalid
          | %{optional(:__struct__) => none(), optional(atom() | binary()) => any()}
        ) :: any()
  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    case %User{}
         |> User.registration_changeset(attrs)
         |> Repo.insert() do
      {:ok, user} ->
        Task.start(fn -> Ysc.Customers.create_stripe_customer(user) end)
        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: true)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  def list_bod_members() do
    from(u in User,
      where: not is_nil(u.board_position),
      order_by: [
        desc: fragment("CASE
          WHEN board_position = 'president' THEN 10
          WHEN board_position = 'vice_president' THEN 9
          WHEN board_position = 'secretary' THEN 8
          WHEN board_position = 'treasurer' THEN 7
          WHEN board_position = 'clear_lake_cabin_master' THEN 6
          WHEN board_position = 'tahoe_cabin_master' THEN 5
          WHEN board_position = 'event_director' THEN 4
          WHEN board_position = 'member_outreach' THEN 3
          WHEN board_position = 'membership_director' THEN 2
          ELSE 1
        END")
      ]
    )
    |> Repo.all()
  end

  def list_paginated_users(params) do
    # Extract membership_type filter if present
    {membership_filters, other_params} = extract_membership_filters(params)
    # Check if sorting by membership_type
    {membership_sort, other_params} = extract_membership_sort(other_params)

    case Flop.validate_and_run(User, other_params, for: User) do
      {:ok, {users, meta}} ->
        # Apply membership filters if any
        filtered_users = apply_membership_filters(users, membership_filters)
        # Preload active subscriptions after the main query
        users_with_subscriptions = preload_active_subscriptions(filtered_users)
        # Apply membership sorting if needed
        sorted_users = apply_membership_sorting(users_with_subscriptions, membership_sort)
        {:ok, {sorted_users, meta}}

      error ->
        error
    end
  end

  defp fuzzy_search_user(search_term) do
    phone_like = "%#{search_term}%"

    from(u in User,
      where: fragment("SIMILARITY(?, ?) > 0.2", u.email, ^search_term),
      or_where: fragment("SIMILARITY(?, ?) > 0.2", u.first_name, ^search_term),
      or_where: fragment("SIMILARITY(?, ?) > 0.2", u.last_name, ^search_term),
      or_where: ilike(u.phone_number, ^phone_like)
    )
  end

  def list_paginated_users(params, nil), do: list_paginated_users(params)

  def list_paginated_users(params, search_term) when search_term == "",
    do: list_paginated_users(params)

  @spec list_paginated_users(
          %{optional(:__struct__) => Flop, optional(atom() | binary()) => any()},
          any()
        ) :: {:error, Flop.Meta.t()} | {:ok, {list(), Flop.Meta.t()}}
  def list_paginated_users(params, search_term) do
    # Extract membership_type filter if present
    {membership_filters, other_params} = extract_membership_filters(params)
    # Check if sorting by membership_type
    {membership_sort, other_params} = extract_membership_sort(other_params)

    case Flop.validate_and_run(fuzzy_search_user(search_term), other_params, for: User) do
      {:ok, {users, meta}} ->
        # Apply membership filters if any
        filtered_users = apply_membership_filters(users, membership_filters)
        # Preload active subscriptions after the main query
        users_with_subscriptions = preload_active_subscriptions(filtered_users)
        # Apply membership sorting if needed
        sorted_users = apply_membership_sorting(users_with_subscriptions, membership_sort)
        {:ok, {sorted_users, meta}}

      error ->
        error
    end
  end

  def update_user(user, params, %User{} = current_user) do
    with :ok <- Policy.authorize(:user_update, current_user, user) do
      user |> User.update_user_changeset(params) |> Repo.update()
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user profile.
  """
  def change_user_profile(user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Updates the user profile information.
  """
  def update_user_profile(user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, [context]))
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1})")
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))

    {:ok, %{to: user.email, text_body: encoded_token}}
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  def update_default_payment_method(user, payment_method_id) do
    payment_method = Ysc.Payments.get_payment_method!(payment_method_id)
    Ysc.Payments.set_default_payment_method(user, payment_method)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/users/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))

      {:ok, %{to: user.email, text_body: encoded_token}}
    end
  end

  def deliver_application_submitted_notification(%User{} = user) do
    YscWeb.Emails.Notifier.schedule_email(
      user.email,
      "#{user.id}",
      "Your Young Scandinavians Club application is in! 🎉",
      "application_submitted",
      %{first_name: String.capitalize(user.first_name)},
      """
      ==============================

      Hi #{String.capitalize(user.first_name)},

      Your application has been submitted! 🎉

      We'll review your application and get back to you soon.

      In the meantime, check out our upcoming events and latest news on our website.

      ==============================
      """,
      user.id
    )
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset-password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))

    {:ok, %{to: user.email, text_body: encoded_token}}
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  def get_signup_application_submission_date(user_id) do
    from(s in SignupApplication,
      select: %{submit_date: s.completed, timezone: s.browser_timezone},
      where: s.user_id == ^user_id
    )
    |> Repo.one()
  end

  def record_application_outcome(:approved, user, application, current_user) do
    with :ok <- Policy.authorize(:signup_application_update, current_user, %{user_id: user.id}) do
      with :ok <- Policy.authorize(:user_update, current_user, %{user_id: user.id}) do
        Ecto.Multi.new()
        |> Ecto.Multi.update(:user, User.update_user_state_changeset(user, %{state: :active}))
        |> Ecto.Multi.update(
          :application,
          SignupApplication.review_outcome_changeset(application, %{
            reviewed_at: DateTime.utc_now(),
            review_outcome: :approved,
            reviewed_by_user_id: current_user.id
          })
        )
        |> Ecto.Multi.insert(
          :application_event,
          SignupApplicationEvent.new_event_changeset(
            %SignupApplicationEvent{},
            %{
              event: :review_completed,
              application_id: application.id,
              user_id: user.id,
              reviewer_user_id: current_user.id,
              result: "approved"
            }
          )
        )
        |> Ecto.Multi.insert(
          :user_event,
          UserEvent.new_user_event_changeset(
            %UserEvent{},
            %{
              user_id: user.id,
              updated_by_user_id: current_user.id,
              type: :state_update,
              from: "#{user.state}",
              to: "active"
            }
          )
        )
        |> Repo.transaction()
        |> case do
          {:ok, _} -> :ok
          {:error, _, changeset, _} -> {:error, changeset}
        end
      end
    end
  end

  def record_application_outcome(:rejected, user, application, current_user) do
    with :ok <- Policy.authorize(:signup_application_update, current_user, %{user_id: user.id}) do
      with :ok <- Policy.authorize(:user_update, current_user, %{user_id: user.id}) do
        Ecto.Multi.new()
        |> Ecto.Multi.update(:user, User.update_user_state_changeset(user, %{state: :rejected}))
        |> Ecto.Multi.update(
          :application,
          SignupApplication.review_outcome_changeset(application, %{
            reviewed_at: DateTime.utc_now(),
            review_outcome: :rejected,
            reviewed_by_user_id: current_user.id
          })
        )
        |> Ecto.Multi.insert(
          :application_event,
          SignupApplicationEvent.new_event_changeset(
            %SignupApplicationEvent{},
            %{
              event: :review_completed,
              application_id: application.id,
              user_id: user.id,
              reviewer_user_id: current_user.id,
              result: "rejected"
            }
          )
        )
        |> Ecto.Multi.insert(
          :user_event,
          UserEvent.new_user_event_changeset(
            %UserEvent{},
            %{
              user_id: user.id,
              updated_by_user_id: current_user.id,
              type: :state_update,
              from: "#{user.state}",
              to: "rejected"
            }
          )
        )
        |> Repo.transaction()
        |> case do
          {:ok, _} -> :ok
          {:error, _, changeset, _} -> {:error, changeset}
        end
      end
    end
  end

  ## Authentication Events

  @doc """
  Gets the datetime of the last successful login for a user.
  Returns nil if no successful login is found.
  """
  def get_last_successful_login_datetime(user) do
    AuthService.get_last_successful_login_datetime(user)
  end

  @doc """
  Gets the last successful login event for a user.
  Returns nil if no successful login is found.
  """
  def get_last_successful_login_event(user) do
    AuthService.get_last_successful_login_event(user)
  end

  @doc """
  Gets recent authentication events for a user.
  """
  def get_user_auth_history(user, limit \\ 50) do
    AuthService.get_user_auth_history(user, limit)
  end

  @doc """
  Gets the last time a user was logged in (either login or logout event).
  This helps determine when the user was last active on the site.
  Returns nil if no login/logout events are found.
  """
  def get_last_login_session_datetime(user) do
    AuthService.get_last_login_session_datetime(user)
  end

  @doc """
  Gets the last login session event for a user (either login or logout).
  This helps determine when the user was last active on the site.
  Returns nil if no login/logout events are found.
  """
  def get_last_login_session_event(user) do
    AuthService.get_last_login_session_event(user)
  end

  @doc """
  Gets the time range when the user was last active on the site.
  Returns a map with :session_start and :session_end datetimes.
  This helps determine what content the user might have missed.
  """
  def get_last_session_timeframe(user) do
    AuthService.get_last_session_timeframe(user)
  end

  # Helper function to preload only active subscriptions
  defp preload_active_subscriptions(users) do
    user_ids = Enum.map(users, & &1.id)

    # Get active subscriptions for all users in one query
    active_subscriptions =
      from(s in Ysc.Subscriptions.Subscription,
        where: s.user_id in ^user_ids,
        where: s.stripe_status in ["active", "trialing", "past_due"],
        preload: [:subscription_items]
      )
      |> Repo.all()

    # Group subscriptions by user_id
    subscriptions_by_user =
      active_subscriptions
      |> Enum.group_by(& &1.user_id)

    # Add subscriptions to each user
    Enum.map(users, fn user ->
      user_subscriptions = Map.get(subscriptions_by_user, user.id, [])
      %{user | subscriptions: user_subscriptions}
    end)
  end

  # Helper function to extract membership_type filters from params
  defp extract_membership_filters(params) do
    case params do
      %{"filters" => filters} when is_map(filters) ->
        # Look for membership_type filter in the filters map
        membership_filter =
          Enum.find_value(filters, fn {_key, filter} ->
            case filter do
              %{"field" => "membership_type", "value" => value}
              when value != "" and value != [""] ->
                # Clean up the value - remove empty strings
                cleaned_value =
                  case value do
                    list when is_list(list) -> Enum.reject(list, &(&1 == ""))
                    other -> other
                  end

                if cleaned_value != [] and cleaned_value != "", do: cleaned_value, else: nil

              _ ->
                nil
            end
          end)

        if membership_filter do
          # Remove the membership_type filter from the filters map
          cleaned_filters =
            Enum.reject(filters, fn {_key, filter} ->
              case filter do
                %{"field" => "membership_type"} -> true
                _ -> false
              end
            end)
            |> Enum.with_index()
            |> Map.new(fn {filter, index} -> {to_string(index), filter} end)

          {membership_filter, Map.put(params, "filters", cleaned_filters)}
        else
          {nil, params}
        end

      _ ->
        {nil, params}
    end
  end

  # Helper function to apply membership filters to users
  defp apply_membership_filters(users, nil), do: users

  defp apply_membership_filters(users, membership_filters) do
    # Get membership plans for price ID lookup
    membership_plans = Application.get_env(:ysc, :membership_plans)
    price_to_type = Map.new(membership_plans, fn plan -> {plan.stripe_price_id, plan.id} end)

    Enum.filter(users, fn user ->
      user_membership_type = get_active_membership_type_for_filter(user, price_to_type)
      user_membership_type in membership_filters
    end)
  end

  # Helper function to get membership type for filtering
  defp get_active_membership_type_for_filter(user, price_to_type) do
    # Get all subscriptions for the user
    subscriptions =
      case user.subscriptions do
        %Ecto.Association.NotLoaded{} -> []
        subscriptions when is_list(subscriptions) -> subscriptions
        _ -> []
      end

    # Filter for active subscriptions only
    active_subscriptions =
      Enum.filter(subscriptions, fn subscription ->
        Ysc.Subscriptions.valid?(subscription)
      end)

    case active_subscriptions do
      [] ->
        :none

      [single_subscription] ->
        get_membership_type_from_subscription_for_filter(single_subscription, price_to_type)

      multiple_subscriptions ->
        # If multiple active subscriptions, pick the most expensive one
        most_expensive = get_most_expensive_subscription_for_filter(multiple_subscriptions)
        get_membership_type_from_subscription_for_filter(most_expensive, price_to_type)
    end
  end

  defp get_membership_type_from_subscription_for_filter(subscription, price_to_type) do
    case subscription.subscription_items do
      [item | _] ->
        Map.get(price_to_type, item.stripe_price_id, :none)

      _ ->
        :none
    end
  end

  defp get_most_expensive_subscription_for_filter(subscriptions) do
    membership_plans = Application.get_env(:ysc, :membership_plans)

    # Create a map of price_id to amount for quick lookup
    price_to_amount =
      Map.new(membership_plans, fn plan ->
        {plan.stripe_price_id, plan.amount}
      end)

    # Find the subscription with the highest amount
    Enum.max_by(subscriptions, fn subscription ->
      # Get the first subscription item (assuming one item per subscription)
      case subscription.subscription_items do
        [item | _] ->
          Map.get(price_to_amount, item.stripe_price_id, 0)

        _ ->
          0
      end
    end)
  end

  # Helper function to extract membership_type sorting from params
  defp extract_membership_sort(params) do
    case params do
      %{"order_by" => order_by, "order_directions" => order_directions} ->
        # Check if membership_type is in the order_by list
        membership_sort_index = Enum.find_index(order_by, &(&1 == "membership_type"))

        if membership_sort_index do
          direction = Enum.at(order_directions, membership_sort_index, :asc)

          # Remove membership_type from order_by and order_directions
          new_order_by = List.delete_at(order_by, membership_sort_index)
          new_order_directions = List.delete_at(order_directions, membership_sort_index)

          new_params =
            params
            |> Map.put("order_by", new_order_by)
            |> Map.put("order_directions", new_order_directions)

          {{:membership_type, direction}, new_params}
        else
          {nil, params}
        end

      _ ->
        {nil, params}
    end
  end

  # Helper function to apply membership sorting to users
  defp apply_membership_sorting(users, nil), do: users

  defp apply_membership_sorting(users, {:membership_type, direction}) do
    # Get membership plans for sorting
    membership_plans = Application.get_env(:ysc, :membership_plans)
    price_to_type = Map.new(membership_plans, fn plan -> {plan.stripe_price_id, plan.id} end)

    # Define sort order for membership types
    membership_sort_order = %{
      :family => 1,
      :single => 2,
      :none => 3
    }

    Enum.sort_by(
      users,
      fn user ->
        membership_type = get_active_membership_type_for_filter(user, price_to_type)
        Map.get(membership_sort_order, membership_type, 4)
      end,
      direction
    )
  end
end
