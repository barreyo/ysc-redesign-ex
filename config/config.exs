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
  metadata: :all

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
  queues: [default: 10, media: 5, exports: 3, mailers: 20],
  log: false,
  plugins: [
    # Maintain for 5 days
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 5},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", YscWeb.Workers.FileExportCleanUp}
     ]}
  ]

config :ex_cldr, default_backend: Ysc.Cldr
config :ex_money, default_cldr_backend: Ysc.Cldr

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role]

config :flop, repo: Ysc.Repo

config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET"),
  public_key: System.get_env("STRIPE_PUBLIC_KEY"),
  webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET")

config :stripity_stripe, :retries, max_attempts: 3, base_backoff: 500, max_backoff: 2_000

# Removed Bling configuration - using internal subscription management

config :ysc, :quickbooks,
  client_id: System.get_env("QUICKBOOKS_CLIENT_ID"),
  client_secret: System.get_env("QUICKBOOKS_CLIENT_SECRET")

config :ysc,
  membership_plans: [
    %{
      id: :single,
      name: "Single",
      interval: "year",
      amount: 45,
      currency: "usd",
      trial_period_days: 0,
      stripe_price_id: "price_1QfrfDIZd8GkARoBcwlNchx4",
      statement_descriptor: "Single Membership",
      description: "Membership just for yourself",
      metadata: %{
        "plan_type" => "membership",
        "interval" => "year"
      }
    },
    %{
      id: :family,
      name: "Family",
      interval: "year",
      amount: 65,
      currency: "usd",
      trial_period_days: 0,
      stripe_price_id: "price_1QfrgWIZd8GkARoB5JBtjoIL",
      statement_descriptor: "Family Membership",
      description: "For you, your Spouse and your children under 18",
      metadata: %{
        "plan_type" => "membership",
        "interval" => "year"
      }
    },
    %{
      id: :lifetime,
      name: "Lifetime",
      interval: "lifetime",
      amount: 0,
      currency: "usd",
      trial_period_days: 0,
      stripe_price_id: nil,
      statement_descriptor: "Lifetime Membership",
      description: "Lifetime membership with all Family membership perks - never expires",
      metadata: %{
        "plan_type" => "membership",
        "interval" => "lifetime"
      }
    }
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
