defmodule YscWeb.Workers.UserExporter do
  require Logger
  use Oban.Worker, queue: :exports, max_attempts: 1

  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Accounts.User
  alias Ysc.Subscriptions.Subscription

  @stream_rows_count 100

  def perform(%_{
        args: %{"channel" => channel, "fields" => fields, "only_subscribed" => only_subscribed}
      }) do
    build_csv(fields, only_subscribed)
    await_csv(channel)

    :ok
  end

  defp build_csv(fields, only_subscribed) do
    job_pid = self()

    # Check how many entries we have to write out
    # helps us report back progress to parent caller
    Task.async(fn ->
      # Build the base query
      base_query = from(u in User)

      # Apply subscription filter if needed
      filtered_query =
        if only_subscribed do
          # Join with subscriptions and filter for users with active subscriptions
          # Check both user.id and user.stripe_id as customer_id
          from(u in User,
            join: s in Subscription,
            on:
              (s.customer_id == fragment("?::text", u.id) or s.customer_id == u.stripe_id) and
                s.customer_type == "user",
            where: s.stripe_status in ["active", "trialing", "past_due"],
            distinct: true
          )
        else
          base_query
        end

      total_count = Repo.one(from q in subquery(filtered_query), select: count(q.id))
      output_path = generate_output_path()
      file = File.open!(output_path, [:write, :utf8])

      Repo.transaction(fn ->
        filtered_query
        |> Repo.stream(max_rows: @stream_rows_count)
        |> Stream.with_index()
        |> Stream.map(fn {entry, index} ->
          build_csv_row(entry, index, fields, job_pid, total_count)
        end)
        |> CSV.encode(headers: true)
        |> Enum.each(&IO.write(file, &1))
      end)

      send(job_pid, {:complete, output_path})

      output_path
    end)
  end

  defp build_csv_row(row, index, fields, pid, total_count) do
    # Only report progress at end of each page
    cond do
      rem(index, @stream_rows_count) == 0 ->
        send(pid, {:progress, trunc(index / total_count * 100)})

      true ->
        nil
    end

    result =
      Enum.reduce(fields, %{}, fn field, acc ->
        field_atom = String.to_existing_atom(field)
        value = Map.get(row, field_atom)
        Map.put(acc, field_atom, value)
      end)

    result
  end

  defp await_csv(channel) do
    receive do
      {:progress, percent} ->
        Logger.info("Broadcasting to `user_export:progress` with value #{percent}")
        YscWeb.Endpoint.broadcast(channel, "user_export:progress", percent)
        await_csv(channel)

      {:complete, export_path} ->
        Logger.info("Broadcasting to `user_export:complete` with value #{export_path}")

        YscWeb.Endpoint.broadcast(
          channel,
          "user_export:complete",
          "/exports/#{Path.basename(export_path)}"
        )
    after
      30_000 ->
        YscWeb.Endpoint.broadcast(channel, "user_export:failed", "Failed to export Users to CSV")
        raise RuntimeError, "No progress after 30s. Giving up."
    end
  end

  defp generate_output_path() do
    ulid = Ecto.ULID.generate()
    time_now = Timex.now()
    formatted_now = Timex.format!(time_now, "%F", :strftime)
    export_directory = "#{:code.priv_dir(:ysc)}/static/exports"
    File.mkdir_p(export_directory)
    "#{export_directory}/ysc-user-export-#{formatted_now}-#{ulid}.csv"
  end
end
