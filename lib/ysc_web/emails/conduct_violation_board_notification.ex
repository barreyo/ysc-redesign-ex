defmodule YscWeb.Emails.ConductViolationBoardNotification do
  use MjmlEEx,
    mjml_template: "templates/conduct_violation_board_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "conduct_violation_board_notification"
  end

  def get_subject() do
    "New Conduct Violation Report - Immediate Board Review Required"
  end

  def admin_dashboard_url() do
    YscWeb.Endpoint.url() <> "/admin"
  end
end
