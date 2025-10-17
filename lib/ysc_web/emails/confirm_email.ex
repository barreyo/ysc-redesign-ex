defmodule YscWeb.Emails.ConfirmEmail do
  use MjmlEEx,
    mjml_template: "templates/confirm_email.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "confirm_email"
  end
end
