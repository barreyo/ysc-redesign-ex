defmodule YscWeb.Emails.VolunteerBoardNotification do
  use MjmlEEx,
    mjml_template: "templates/volunteer_board_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "volunteer_board_notification"
  end

  def get_subject() do
    "New Volunteer Signup - YSC Board Review"
  end

  def admin_dashboard_url() do
    YscWeb.Endpoint.url() <> "/admin"
  end
end
