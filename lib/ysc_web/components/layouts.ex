defmodule YscWeb.Layouts do
  use YscWeb, :html

  embed_templates "layouts/*"

  def fullscreen?(conn) do
    current_path = Path.join(["/" | conn.path_info])

    String.starts_with?(current_path, [
      "/users/log_in",
      "/users/register",
      "/users/reset_password"
    ])
  end
end
