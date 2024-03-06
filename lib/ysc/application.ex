defmodule Ysc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Oban.Telemetry.attach_default_logger()

    children = [
      # Start the Telemetry supervisor
      YscWeb.Telemetry,
      # Start the Ecto repository
      Ysc.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Ysc.PubSub},
      # Start Finch
      {Finch, name: Ysc.Finch},
      # Start the Endpoint (http/https)
      YscWeb.Endpoint,
      # Start a worker by calling: Ysc.Worker.start_link(arg)
      # {Ysc.Worker, arg}
      {Oban, Application.fetch_env!(:ysc, Oban)}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ysc.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    YscWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
