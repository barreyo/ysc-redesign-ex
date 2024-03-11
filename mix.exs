defmodule Ysc.MixProject do
  use Mix.Project

  def project do
    [
      app: :ysc,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Ysc.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:argon2_elixir, "~> 4.0"},
      {:blurhash, "~> 0.1.0", hex: :rinpatch_blurhash},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:csv, "~> 3.2"},
      {:ecto_enum, "~> 1.4"},
      {:ecto_psql_extras, "~> 0.6"},
      {:ecto_sql, "~> 3.11"},
      {:ecto_ulid, "~> 0.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:ex_aws_s3, "~> 2.0"},
      {:ex_aws, "~> 2.1"},
      {:ex_money_sql, "~> 1.0"},
      {:ex_phone_number, "~> 0.4"},
      {:finch, "~> 0.17"},
      {:floki, ">= 0.30.0", only: :test},
      {:flop_phoenix, "~> 0.22.7"},
      {:gettext, "~> 0.24"},
      {:hackney, "~> 1.9"},
      {:image, "~> 0.37"},
      {:iso, ">= 0.0.0"},
      {:jason, "~> 1.4"},
      {:let_me, "~> 1.2.3"},
      {:mogrify, "~> 0.8.0"},
      {:oban, "~> 2.17"},
      {:phoenix_bakery, "~> 0.1", runtime: false},
      {:phoenix_ecto, "~> 4.4"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_reload, "~> 1.4", only: :dev},
      {:phoenix_live_view,
       git: "https://github.com/phoenixframework/phoenix_live_view.git",
       branch: "main",
       override: true},
      {:phoenix, "~> 1.7"},
      {:plug_cowboy, "~> 2.6"},
      {:postgrex, ">= 0.0.0"},
      {:swoosh, "~> 1.14"},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:timex, "~> 3.7"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end
end
