defmodule YscWeb.Emails.ResetPassword do
  use MjmlEEx,
    mjml_template: "templates/reset_password.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "reset_password"
  end
end
