defmodule YscWeb.Emails.ApplicationApproved do
  use MjmlEEx,
    mjml_template: "templates/application_approved.mjml.heex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "application_approved"
  end

  def get_subject() do
    "Velkommen! You're officially a Young Scandinavian 🎉 (One more step!)"
  end

  defp upcoming_events_url() do
    YscWeb.Endpoint.url() <> "/events"
  end

  defp pay_membership_url() do
    YscWeb.Endpoint.url() <> "/users/membership"
  end
end
