defmodule YscWeb.PageController do
  use YscWeb, :controller

  use Timex

  def home(conn, _params) do
    render(conn, :home)
  end

  def pending_review(conn, _params) do
    current_user = conn.assigns.current_user

    submitted_application_at =
      Ysc.Accounts.get_signup_application_submission_date(current_user.id)

    submitted_date = submitted_application_at[:submit_date]

    timezone =
      case submitted_application_at[:timezone] do
        nil -> "America/Los_Angeles"
        v -> v
      end

    local_date = Timex.Timezone.convert(submitted_date, timezone)
    days_ago = Timex.from_now(submitted_date)

    conn
    |> assign(:application_submitted_date, local_date)
    |> assign(:time_delta, days_ago)
    |> render(:pending_review)
  end
end
