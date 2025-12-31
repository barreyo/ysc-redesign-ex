defmodule YscWeb.Layouts do
  use YscWeb, :html

  embed_templates "layouts/*"

  def fullscreen?(conn_or_path) when is_binary(conn_or_path) do
    String.starts_with?(conn_or_path, [
      "/users/log-in",
      "/users/register",
      "/users/reset-password",
      "/users/settings/confirm-email",
      "/users/log-in/auto",
      "/account/setup",
      "/report-conduct-violation"
    ])
  end

  def fullscreen?(%Plug.Conn{} = conn) do
    current_path = Path.join(["/" | conn.path_info])
    fullscreen?(current_path)
  end

  def fullscreen?(_), do: false
end
