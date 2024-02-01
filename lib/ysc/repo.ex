defmodule Ysc.Repo do
  use Ecto.Repo,
    otp_app: :ysc,
    adapter: Ecto.Adapters.Postgres
end
