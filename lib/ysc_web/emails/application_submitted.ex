defmodule YscWeb.Emails.ApplicationSubmitted do
  use MjmlEEx,
    mjml_template: "templates/application_submitted.mjml.heex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Settings

  def get_template_name() do
    "application_submitted"
  end

  def get_subject() do
    "Your Young Scandinavians Club application is in! 🎉"
  end

  defp upcoming_events_url() do
    YscWeb.Endpoint.url() <> "/events"
  end

  defp latest_news_url() do
    YscWeb.Endpoint.url() <> "/news"
  end

  defp facebook_path() do
    Settings.get_setting("facebook")
  end

  defp instagram_path() do
    Settings.get_setting("instagram")
  end
end
