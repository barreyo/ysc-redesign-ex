defmodule YscWeb.Workers.EmailNotifier do
  require Logger
  use Oban.Worker, queue: :mailers, max_attempts: 3

  def perform(%Oban.Job{
        args:
          %{
            "recipient" => recipient,
            "idempotency_key" => idempotency_key,
            "subject" => subject,
            "template" => template,
            "params" => params,
            "text_body" => text_body,
            "user_id" => user_id
          } = _args
      }) do
    template_module = YscWeb.Emails.Notifier.get_template_module(template)
    atomized_params = atomize_keys(params)

    YscWeb.Emails.Notifier.send_email_idempotent(
      recipient,
      idempotency_key,
      subject,
      template_module,
      atomized_params,
      text_body,
      user_id
    )

    :ok
  end

  def atomize_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {String.to_atom(key), atomize_keys(value)}
    end)
  end

  def atomize_keys(other) do
    other
  end
end
