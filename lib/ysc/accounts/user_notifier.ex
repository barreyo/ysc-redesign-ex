defmodule Ysc.Accounts.UserNotifier do
  @moduledoc """
  User notification service.

  Handles sending various notification emails to users including confirmation,
  password reset, and account-related notifications.
  """
  alias YscWeb.Emails.Notifier

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    Notifier.schedule_email(
      user.email,
      "#{user.id}",
      "Confirm Your YSC Account",
      "confirm_email",
      %{first_name: String.capitalize(user.first_name), url: url},
      """
      ==============================

      Hi #{user.email},

      You can confirm your account by visiting the URL below:

      #{url}

      If you didn't create an account with us, please ignore this.

      ==============================
      """,
      user.id
    )

    url
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    Notifier.schedule_email(
      user.email,
      UUID.uuid4(),
      "Reset Your YSC Password",
      "reset_password",
      %{first_name: String.capitalize(user.first_name), url: url},
      """
      ==============================

      Hi #{user.email},

      You can reset your password by visiting the URL below:

      #{url}

      If you didn't request this change, please ignore this.

      ==============================
      """,
      user.id
    )

    url
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    Notifier.schedule_email(
      user.email,
      UUID.uuid4(),
      "Change Your YSC Email",
      "change_email",
      %{first_name: String.capitalize(user.first_name), url: url},
      """
      ==============================

      Hi #{user.email},

      You can update your email by visiting the URL below:

      #{url}

      If you didn't request this change, please ignore this.

      ==============================
      """,
      user.id
    )

    url
  end

  @doc """
  Deliver password changed notification to a user.
  """
  def deliver_password_changed_notification(user) do
    Notifier.schedule_email(
      user.email,
      UUID.uuid4(),
      "Your YSC Password Has Been Changed",
      "password_changed",
      %{first_name: String.capitalize(user.first_name)},
      """
      ==============================

      Hi #{user.email},

      This is to confirm that your password for the Young Scandinavians Club account has been successfully changed.

      If you did not make this change, please contact us immediately at info@ysc.org so we can secure your account.

      If you did change your password, you can safely ignore this notification.

      ==============================
      """,
      user.id
    )
  end

  @doc """
  Deliver email changed notification to a user.
  """
  def deliver_email_changed_notification(user, new_email) do
    Notifier.schedule_email(
      new_email,
      UUID.uuid4(),
      "Your YSC Email Has Been Changed",
      "email_changed",
      %{first_name: String.capitalize(user.first_name), new_email: new_email},
      """
      ==============================

      Hi #{new_email},

      This is to confirm that the email address for your Young Scandinavians Club account has been successfully changed to #{new_email}.

      If you did not make this change, please contact us immediately at info@ysc.org so we can secure your account.

      If you did change your email, you can safely ignore this notification.

      ==============================
      """,
      user.id
    )
  end
end
