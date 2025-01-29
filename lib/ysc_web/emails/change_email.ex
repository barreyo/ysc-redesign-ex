defmodule YscWeb.Emails.ChangeEmail do
  use MjmlEEx,
    mjml_template: "templates/change_email.mjml.heex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "change_email"
  end
end
