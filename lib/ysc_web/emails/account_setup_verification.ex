defmodule YscWeb.Emails.AccountSetupVerification do
  @moduledoc """
  Email template for account setup email verification.

  Sends a verification code to users for verifying their email address during account setup.
  """
  use MjmlEEx,
    mjml_template: "templates/account_setup_verification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "account_setup_verification"
  end
end
