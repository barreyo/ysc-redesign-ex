defmodule Ysc.PropertyOutages.OutageScraperWorker do
  @moduledoc """
  Oban worker for scraping property outage information.

  Runs every 30 minutes to fetch the latest outage data from various
  utility providers and update the database.
  """

  require Logger
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Ysc.PropertyOutages.Scraper

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    Logger.info("Starting outage scraper job", job_id: job.id)

    case Scraper.scrape_all() do
      {:ok, results} ->
        Logger.info("Outage scraper job completed successfully", job_id: job.id)
        :ok

      {:error, reason} ->
        Logger.error("Outage scraper job failed",
          job_id: job.id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job) do
    # Job timeout after 5 minutes
    5 * 60 * 1000
  end
end
