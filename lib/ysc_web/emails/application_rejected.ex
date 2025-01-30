defmodule YscWeb.Emails.ApplicationRejected do
  use MjmlEEx,
    mjml_template: "templates/application_rejected.mjml.heex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "application_rejected"
  end

  def get_subject() do
    "Update on your Young Scandinavians Club application"
  end
end
