defmodule Ysc.Accounts.UserNotifier do
  alias YscWeb.Emails.Notifier

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    Notifier.send_email_idempotent(
      user.email,
      "#{user.id}",
      "Confirm Your YSC Account",
      YscWeb.Emails.ConfirmEmail,
      %{first_name: user.first_name, url: url},
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
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    Notifier.send_email_idempotent(
      user.email,
      UUID.uuid4(),
      "Reset Your YSC Password",
      YscWeb.Emails.ResetPassword,
      %{first_name: user.first_name, url: url},
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
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    Notifier.send_email_idempotent(
      user.email,
      # Making idempotency irrelevant
      UUID.uuid4(),
      "Change Your YSC Email",
      YscWeb.Emails.ChangeEmail,
      %{first_name: user.first_name, url: url},
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
  end
end
