defmodule Ysc.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      YscWeb.Telemetry,
      # Start the Ecto repository
      Ysc.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Ysc.PubSub},
      # Start DNS cluster to cluster the app
      {DNSCluster, query: Application.get_env(:ysc, :dns_cluster_query) || :ignore},
      # Start Finch
      {Finch, name: Ysc.Finch},
      # Start cache
      {Cachex, name: :ysc_cache},
      # Start the Endpoint (http/https)
      YscWeb.Endpoint,
      # Start a worker by calling: Ysc.Worker.start_link(arg)
      # {Ysc.Worker, arg}
      {Oban, Application.fetch_env!(:ysc, Oban)}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ysc.Supervisor]
    {:ok, supervisor} = Supervisor.start_link(children, opts)

    # Start the ticket timeout scheduler
    Ysc.Tickets.Scheduler.start_scheduler()

    # Start the outage scraper scheduler
    Ysc.PropertyOutages.Scheduler.start_scheduler()

    {:ok, supervisor}
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    YscWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
