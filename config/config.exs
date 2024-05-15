# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ysc,
  ecto_repos: [Ysc.Repo]

config :ysc, Ysc.Repo, migration_timestamps: [type: :utc_datetime]

# Configures the endpoint
config :ysc, YscWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: YscWeb.ErrorHTML, json: YscWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Ysc.PubSub,
  live_view: [signing_salt: "CTGAp6Hk"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :ysc, Ysc.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.3.2",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :phoenix,
  static_compressors: [
    PhoenixBakery.Brotli
  ]

config :argon2_elixir,
  argon2_type: 1

config :ysc, Oban,
  repo: Ysc.Repo,
  queues: [default: 10, media: 5, exports: 3],
  plugins: [
    # Maintain for 5 days
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 5},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", YscWeb.Workers.FileExportCleanUp}
     ]}
  ]

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role]

config :flop, repo: Ysc.Repo

config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET")

config :stripity_stripe, :retries, max_attempts: 3, base_backoff: 500, max_backoff: 2_000

config :ysc, :quickbooks,
  client_id: System.get_env("QUICKBOOKS_CLIENT_ID"),
  client_secret: System.get_env("QUICKBOOKS_CLIENT_SECRET")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
