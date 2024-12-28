defmodule YscWeb.Components.Image do
  use YscWeb, :live_component

  alias Ysc.Media.Image
  alias Ysc.Media

  def render(assigns) do
    ~H"""
    <div class="relative w-full h-full">
      <canvas
        id={"blur-hash-image-#{@id}"}
        src={get_blur_hash(@image)}
        class="absolute left-0 top-0 rounded-lg w-full h-full object-center aspect-video"
        phx-hook="BlurHashCanvas"
      >
      </canvas>

      <img
        src={image_url(@image)}
        id={"image-#{@id}"}
        loading="lazy"
        phx-hook="BlurHashImage"
        class="object-cover rounded-lg w-full object-center aspect-video"
      />
    </div>
    """
  end

  def update(assigns, socket) do
    if assigns.image_id == nil || assigns.image_id == "" do
      {:ok, socket |> assign(assigns) |> assign(image: nil)}
    else
      image = Media.get_image!(assigns.image_id)
      {:ok, socket |> assign(assigns) |> assign(image: image)}
    end
  end

  defp get_blur_hash(nil), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: nil}), do: "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
  defp get_blur_hash(%Image{blur_hash: blur_hash}), do: blur_hash

  defp image_url(nil), do: "/images/ysc_logo.png"
  defp image_url(%Image{optimized_image_path: nil} = image), do: image.raw_image_path
  defp image_url(%Image{optimized_image_path: optimized_path}), do: optimized_path
end
