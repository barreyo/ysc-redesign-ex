defmodule YscWeb.Emails.ConductViolationConfirmation do
  use MjmlEEx,
    mjml_template: "templates/conduct_violation_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "conduct_violation_confirmation"
  end

  def get_subject() do
    "Conduct Violation Report Received - YSC"
  end

  def code_of_conduct_url() do
    YscWeb.Endpoint.url() <> "/code-of-conduct"
  end

  def contact_url() do
    YscWeb.Endpoint.url() <> "/contact"
  end
end
