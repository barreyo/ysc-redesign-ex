defmodule Ysc.Accounts.Behaviour do
  @callback get_signup_application_submission_date(integer()) :: %{
              submit_date: DateTime.t(),
              timezone: String.t() | nil
            }
end
