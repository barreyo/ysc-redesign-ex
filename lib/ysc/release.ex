defmodule Ysc.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :ysc

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def seed do
    load_app()

    seeds_path = Path.join([:code.priv_dir(@app), "repo", "seeds_prod.exs"])

    if File.exists?(seeds_path) do
      for repo <- repos() do
        {:ok, _, _} =
          Ecto.Migrator.with_repo(repo, fn _repo ->
            Code.eval_file(seeds_path)
          end)
      end
    else
      IO.puts("Warning: seeds file not found at #{seeds_path}")
    end
  end

  @doc """
  Re-queues all failed email messages.

  Usage in production:
      bin/ysc eval "Ysc.Release.requeue_failed_messages()"

  Or with options:
      bin/ysc eval "Ysc.Release.requeue_failed_messages(limit: 50)"
  """
  def requeue_failed_messages(opts \\ []) do
    load_app()

    require Logger

    Logger.info("Re-queuing failed email messages...")

    result = Ysc.Messages.Requeue.requeue_all(opts)

    Logger.info("Summary:")
    Logger.info("Total Found: #{result.total_found}")
    Logger.info("Successfully Re-queued: #{result.successful}")
    Logger.info("Failed to Re-queue: #{result.failed}")

    if result.failed > 0 do
      Logger.warning("Some jobs failed to re-queue. Check logs for details.")
    end

    result
  end

  @doc """
  Shows statistics about failed email messages.

  Usage in production:
      bin/ysc eval "Ysc.Release.show_failed_message_stats()"
  """
  def show_failed_message_stats do
    load_app()

    require Logger

    stats = Ysc.Messages.Requeue.get_stats()

    Logger.info("Failed email job statistics:")
    Logger.info("Total Failed: #{stats.total_failed}")
    Logger.info("Discarded (exhausted retries): #{stats.discarded}")
    Logger.info("Retryable (can still retry): #{stats.retryable}")
    Logger.info("Recent Failures (24h): #{stats.recent_failures_24h}")

    if not Enum.empty?(stats.by_template) do
      Logger.info("By Template:")

      Enum.each(stats.by_template, fn {template, count} ->
        Logger.info("  #{template}: #{count}")
      end)
    end

    stats
  end

  @doc """
  Re-queues a single failed email message by job ID.

  Usage in production:
      bin/ysc eval "Ysc.Release.requeue_failed_message(JOB_ID)"
  """
  def requeue_failed_message(job_id) do
    load_app()

    require Logger

    Logger.info("Re-queuing job: #{job_id}")

    case Ysc.Messages.Requeue.requeue_job_by_id(job_id) do
      {:ok, new_job} ->
        Logger.info("✅ Successfully re-queued job #{job_id}")
        Logger.info("New Job ID: #{new_job.id}")
        {:ok, new_job}

      {:error, :not_found} ->
        Logger.error("❌ Job #{job_id} not found")
        {:error, :not_found}

      {:error, :not_an_email_job} ->
        Logger.error("❌ Job #{job_id} is not an email job")
        {:error, :not_an_email_job}

      {:error, reason} ->
        Logger.error("❌ Failed to re-queue job #{job_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
