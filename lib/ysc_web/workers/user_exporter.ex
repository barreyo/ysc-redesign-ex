defmodule YscWeb.Workers.UserExporter do
  @moduledoc """
  Oban worker for exporting user data to CSV format.

  Handles asynchronous export of user information with customizable fields
  and filtering options.
  """
  require Logger
  use Oban.Worker, queue: :exports, max_attempts: 1

  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Accounts.User
  alias Ysc.Accounts
  alias Ysc.Subscriptions
  alias Ysc.Subscriptions.Subscription

  @stream_rows_count 100

  def perform(%_{
        args: %{"channel" => channel, "fields" => fields, "only_subscribed" => only_subscribed}
      }) do
    Logger.info(
      "UserExporter: Starting export with fields: #{inspect(fields)}, only_subscribed: #{only_subscribed}"
    )

    try do
      build_csv(fields, only_subscribed)
      await_csv(channel)
      :ok
    rescue
      e ->
        Logger.error("UserExporter: Error during export: #{inspect(e)}")
        Logger.error(Exception.format(:error, e, __STACKTRACE__))

        YscWeb.Endpoint.broadcast(
          channel,
          "user_export:failed",
          "Export failed: #{Exception.message(e)}"
        )

        {:error, e}
    end
  end

  defp build_csv(fields, only_subscribed) do
    job_pid = self()
    Logger.info("UserExporter: Starting build_csv")

    # Check how many entries we have to write out
    # helps us report back progress to parent caller
    Task.async(fn ->
      Logger.info("UserExporter: Task started")
      # Build the base query (without preloads for counting)
      base_query = from(u in User)

      # Apply subscription filter if needed
      filtered_query =
        if only_subscribed do
          # Include users with:
          # 1. Active subscriptions (active, trialing, past_due)
          # 2. Lifetime membership (lifetime_membership_awarded_at is not null)
          from(u in User,
            left_join: s in Subscription,
            on: s.user_id == u.id,
            where:
              s.stripe_status in ["active", "trialing", "past_due"] or
                not is_nil(u.lifetime_membership_awarded_at),
            distinct: true
          )
        else
          base_query
        end

      # Count without preloads (can't use preloads in subquery)
      total_count = Repo.one(from q in subquery(filtered_query), select: count(q.id))
      Logger.info("UserExporter: Total count: #{total_count}")

      output_path = generate_output_path()
      Logger.info("UserExporter: Output path: #{output_path}")
      file = File.open!(output_path, [:write, :utf8])

      # Note: Can't use preloads in streams, so we'll load subscriptions manually
      Repo.transaction(fn ->
        filtered_query
        |> Repo.stream(max_rows: @stream_rows_count)
        |> Stream.map(fn user ->
          # Load subscriptions with subscription_items for this user
          user
          |> Repo.preload(subscriptions: [:subscription_items])
        end)
        |> Stream.with_index()
        |> Stream.map(fn {entry, index} ->
          build_csv_row(entry, index, fields, job_pid, total_count)
        end)
        |> CSV.encode(headers: true)
        |> Enum.each(&IO.write(file, &1))
      end)

      File.close(file)
      Logger.info("UserExporter: File written and closed")

      send(job_pid, {:complete, output_path})

      output_path
    end)
  end

  defp build_csv_row(row, index, fields, pid, total_count) do
    # Only report progress at end of each page
    if rem(index, @stream_rows_count) == 0 do
      send(pid, {:progress, trunc(index / total_count * 100)})
    end

    # Get membership info for this user
    {membership_type, renewal_date} = get_membership_info(row)

    # Build result with standard fields
    # Fields come in as atoms from AdminUsersLive
    result =
      Enum.reduce(fields, %{}, fn field, acc ->
        field_atom =
          case field do
            field when is_atom(field) -> field
            field when is_binary(field) -> String.to_existing_atom(field)
          end

        value = Map.get(row, field_atom)
        Map.put(acc, field_atom, value)
      end)

    # Add membership columns
    result
    |> Map.put(:membership_type, membership_type)
    |> Map.put(:membership_renewal_date, renewal_date)
  end

  defp get_membership_info(user) do
    # Check for lifetime membership first
    if Accounts.has_lifetime_membership?(user) do
      {"Lifetime", "Never"}
    else
      # Use preloaded subscriptions if available, otherwise query
      subscriptions =
        case user.subscriptions do
          %Ecto.Association.NotLoaded{} ->
            # Subscriptions not preloaded, fetch them
            Subscriptions.list_subscriptions(user)

          subscriptions when is_list(subscriptions) ->
            # Subscriptions already preloaded
            subscriptions

          _ ->
            []
        end

      # Find active subscription
      active_subscription =
        subscriptions
        |> Enum.find(&Subscriptions.active?/1)

      case active_subscription do
        nil ->
          {nil, nil}

        subscription ->
          # Ensure subscription items are loaded
          subscription =
            if Ecto.assoc_loaded?(subscription.subscription_items) do
              subscription
            else
              Repo.preload(subscription, :subscription_items)
            end

          membership_type = get_membership_type_from_subscription(subscription)
          renewal_date = format_renewal_date(subscription.current_period_end)

          {membership_type, renewal_date}
      end
    end
  end

  defp get_membership_type_from_subscription(subscription) do
    case subscription.subscription_items do
      [item | _] ->
        membership_plans = Application.get_env(:ysc, :membership_plans, [])

        case Enum.find(membership_plans, &(&1.stripe_price_id == item.stripe_price_id)) do
          %{name: name} -> name
          _ -> "Unknown"
        end

      _ ->
        nil
    end
  end

  defp format_renewal_date(nil), do: nil

  defp format_renewal_date(%DateTime{} = datetime) do
    # Format in America/Los_Angeles timezone for display
    datetime
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> Timex.format!("%Y-%m-%d %I:%M %p %Z", :strftime)
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
