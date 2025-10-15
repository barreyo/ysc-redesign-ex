defmodule YscWeb.Emails.MembershipPaymentFailure do
  use MjmlEEx,
    mjml_template: "templates/membership_payment_failure.mjml.heex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "membership_payment_failure"
  end

  def get_subject() do
    "Action Needed: YSC Membership Payment Issue"
  end

  def pay_membership_url() do
    YscWeb.Endpoint.url() <> "/users/membership"
  end
end
