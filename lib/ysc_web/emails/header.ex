defmodule YscWeb.Emails.HeaderBlock do
  use MjmlEEx.Component, mode: :runtime

  @impl MjmlEEx.Component
  def render(_assigns) do
    """
    <mj-section padding="32px">
      <mj-column padding="0">
        <mj-image padding="0px" src="#{logo_path()}" width="120px"></mj-image>
      </mj-column>
    </mj-section>
    """
  end

  defp logo_path() do
    "#{YscWeb.Endpoint.url()}/images/ysc_logo.png"
  end
end
