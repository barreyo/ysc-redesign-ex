defmodule YscWeb.Workers.ImageProcessor do
  @moduledoc """
  Oban worker for processing and optimizing images.

  Handles image transformations, resizing, and optimization tasks asynchronously.
  """
  require Logger

  use Oban.Worker, queue: :media

  alias HTTP
  alias Ysc.Media

  @temp_dir "/tmp/image_processor"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id} = _args}) do
    image = Media.fetch_image(id)

    tmp_output_file = "#{@temp_dir}/#{image.id}"
    optimized_output_path = "#{tmp_output_file}_optimized.png"
    thumbnail_output_path = "#{tmp_output_file}_thumb.png"

    Logger.info(tmp_output_file)
    Logger.info(optimized_output_path)
    Logger.info(thumbnail_output_path)

    make_temp_dir(@temp_dir)

    Logger.info("Started work on Image: #{image.id}")

    try do
      # Start working on this image
      Media.set_image_processing_state(image, :processing)

      # Download from the internet and cache locally
      {:ok, :saved_to_file} =
        :httpc.request(:get, {to_charlist(URI.encode(image.raw_image_path)), []}, [],
          stream: to_charlist(tmp_output_file)
        )

      Media.process_image_upload(
        image,
        tmp_output_file,
        thumbnail_output_path,
        optimized_output_path
      )

      :ok
    after
      Logger.info("Cleaning up generated files")
      File.rm(tmp_output_file)
      File.rm(optimized_output_path)
      File.rm(thumbnail_output_path)
    end
  end

  defp make_temp_dir(path) do
    File.mkdir(path)
  end
end
