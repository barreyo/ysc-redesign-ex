defmodule YscWeb.Workers.ImageProcessor do
  require Logger

  use Oban.Worker, queue: :media

  alias HTTP
  alias Ysc.Media

  @bucket_name "media"
  @temp_dir "/tmp/image_processor"

  @blur_hash_comp_x 4
  @blur_hash_comp_y 3
  @thumbnail_size 500

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
        :httpc.request(:get, {to_charlist(image.raw_image_path), []}, [],
          stream: to_charlist(tmp_output_file)
        )

      {:ok, parsed_image} = Image.open(tmp_output_file)
      {:ok, meta_free_image} = Image.remove_metadata(parsed_image)

      Image.write(meta_free_image, optimized_output_path, minimize_file_size: true)

      {:ok, thumbnail_image} = Image.thumbnail(meta_free_image, @thumbnail_size)
      Image.write(thumbnail_image, thumbnail_output_path)

      width = Image.width(parsed_image)
      height = Image.height(parsed_image)

      upload_result =
        upload_files_to_s3(
          thumbnail: thumbnail_output_path,
          optimized: optimized_output_path
        )

      # Downscale to very small and generate blurhash
      blur_hash = generate_blur_hash(tmp_output_file)

      Logger.info("Writing results to DB")

      Media.update_processed_image(image, %{
        optimized_image_path: upload_result[:optimized],
        thumbnail_path: upload_result[:thumbnail],
        blur_hash: blur_hash,
        width: width,
        height: height,
        processing_state: "completed"
      })

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

  defp upload_file_to_s3(path) do
    file_name = Path.basename(path)

    path
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(@bucket_name, file_name)
    |> ExAws.request!()
  end

  defp upload_files_to_s3(files) do
    Enum.map(files, fn {k, v} ->
      {k, upload_file_to_s3(v)[:body][:location]}
    end)
  end

  defp generate_blur_hash(path) do
    {:ok, blur_hash} = Blurhash.downscale_and_encode(path, @blur_hash_comp_x, @blur_hash_comp_y)
    blur_hash
  end
end
