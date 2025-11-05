defmodule YscWeb.Components.Image do
  @moduledoc """
  LiveView component for displaying images with blur hash placeholders.

  Renders images with progressive loading using blur hash placeholders.
  """
  use YscWeb, :live_component

  alias Ysc.Media.Image
  alias Ysc.Media

  def render(assigns) do
    ~H"""
    <div class={"relative w-full #{@aspect_class}"}>
      <canvas
        id={"blur-hash-image-#{@id}"}
        src={get_blur_hash(@image)}
        class="absolute inset-0 z-0 rounded-lg w-full h-full object-cover"
        phx-hook="BlurHashCanvas"
      >
      </canvas>

      <img
        src={image_url(@image)}
        id={"image-#{@id}"}
        loading="lazy"
        phx-hook="BlurHashImage"
        class="absolute inset-0 z-[1] opacity-0 transition-opacity duration-300 ease-out rounded-lg w-full h-full object-cover"
      />
    </div>
    """
  end

  def update(assigns, socket) do
    socket = socket |> assign(assigns)

    aspect_class = Map.get(assigns, :aspect_class, "aspect-video")
    socket = assign(socket, :aspect_class, aspect_class)

    if assigns.image_id == nil || assigns.image_id == "" do
      {:ok, socket |> assign(image: nil)}
    else
      image = Media.get_image!(assigns.image_id)
      {:ok, socket |> assign(image: image)}
    end
  end

  defp get_blur_hash(nil), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash

  defp image_url(nil), do: "/images/ysc_logo.png"
  defp image_url(%Image{optimized_image_path: nil} = image), do: image.raw_image_path
  defp image_url(%Image{optimized_image_path: optimized_path}), do: optimized_path
end
