defmodule YscWeb.Emails.MembershipPaymentFailure do
  @moduledoc """
  Email template for membership payment failure notification.

  Notifies users when a membership payment fails.
  """
  use MjmlEEx,
    mjml_template: "templates/membership_payment_failure.mjml.eex",
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
