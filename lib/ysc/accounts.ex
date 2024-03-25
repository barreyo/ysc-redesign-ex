defmodule Ysc.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false

  alias Ysc.Accounts.UserEvent
  alias Ysc.Accounts.SignupApplicationEvent
  alias YscWeb.Authorization.Policy
  alias Ysc.Accounts.SignupApplication
  alias Ysc.Repo

  alias Ysc.Accounts.{User, UserToken, UserNotifier}

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
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
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

  def list_paginated_users(params) do
    Flop.validate_and_run(User, params, for: User)
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
    Flop.validate_and_run(fuzzy_search_user(search_term), params, for: User)
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

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1})")
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
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
    end
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

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
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
              reviewer_user_id: current_user.id
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
              reviewer_user_id: current_user.id
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

  defp maybe_populate_display_name(%User{first_name: nil, last_name: nil} = user), do: user

  defp maybe_populate_display_name(%User{first_name: nil, last_name: last} = user),
    do: %{user | display_name: String.capitalize(String.downcase(last))}

  defp maybe_populate_display_name(%User{first_name: first, last_name: nil} = user),
    do: %{user | display_name: String.capitalize(String.downcase(first))}

  defp maybe_populate_display_name(%User{first_name: first, last_name: last} = user),
    do: %{
      user
      | display_name:
          "#{String.capitalize(String.downcase(first))} #{String.capitalize(String.downcase(last))}"
    }
end
