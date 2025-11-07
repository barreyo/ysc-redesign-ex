defmodule Ysc.Media do
  @moduledoc """
  Context module for managing media files and images.

  Handles image upload, storage, processing, and retrieval operations.
  """
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Media
  alias Ysc.S3Config
  alias YscWeb.Authorization.Policy
  alias Ysc.Accounts.User

  @blur_hash_comp_x 4
  @blur_hash_comp_y 3
  @thumbnail_size 500
  @max_optimized_width 1920
  @max_optimized_height 1920
  @optimized_quality 85

  def list_images() do
    {:ok, Media.Image |> order_by(desc: :id) |> Repo.all()}
  end

  def list_images(offset, limit) do
    Repo.all(
      from i in Media.Image,
        order_by: [{:desc, :inserted_at}],
        limit: ^limit,
        offset: ^offset
    )
  end

  @doc """
  Count the number of published events.
  """
  def count_images do
    Media.Image
    |> Repo.aggregate(:count, :id)
  end

  @spec list_images_per_year() :: any()
  def list_images_per_year() do
    {:ok, images} = list_images()

    Enum.reduce(images, %{}, fn image, new_map ->
      year = image.inserted_at.year
      c = Map.get(new_map, year, [])
      Map.put(new_map, year, [image | c])
    end)
  end

  @spec fetch_image(any()) :: any()
  def fetch_image(id) do
    Repo.get(Media.Image, id)
  end

  def get_image!(id) do
    Repo.get!(Media.Image, id)
  end

  def add_new_image(attrs, %User{} = current_user) do
    with :ok <- Policy.authorize(:media_image_create, current_user) do
      %Media.Image{}
      |> Media.Image.add_image_changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_image(%Media.Image{} = image, attrs, %User{} = current_user) do
    with :ok <- Policy.authorize(:media_image_update, current_user, image) do
      image
      |> Media.Image.edit_image_changeset(attrs)
      |> Repo.update()
    end
  end

  def delete_image(%Media.Image{} = image, %User{} = current_user) do
    with :ok <- Policy.authorize(:media_image_delete, current_user, image) do
      Repo.delete(image)
    end
  end

  def set_image_processing_state(%Media.Image{} = image, state) do
    Repo.update(Media.Image.image_processing_state_changeset(image, state))
  end

  def update_processed_image(%Media.Image{} = image, attrs) do
    changeset = Media.Image.processed_image_changeset(image, attrs)
    Repo.update!(changeset)
  end

  def process_image_upload(
        %Media.Image{} = image,
        path,
        thumbnail_output_path,
        optimized_output_path
      ) do
    {:ok, parsed_image} = Image.open(path)
    {:ok, meta_free_image} = Image.remove_metadata(parsed_image)

    # Get original dimensions
    original_width = Image.width(parsed_image)
    original_height = Image.height(parsed_image)

    # Detect original format from file extension
    original_format = detect_image_format(path)

    # Determine output format - prefer WEBP for better compression, fallback to original format
    output_format = determine_output_format(original_format)

    # Ensure optimized output path uses correct extension
    optimized_output_path = ensure_format_extension(optimized_output_path, output_format)
    thumbnail_output_path = ensure_format_extension(thumbnail_output_path, output_format)

    # Create optimized version: maintain aspect ratio, cap at max dimensions, preserve quality
    optimized_image =
      if original_width > @max_optimized_width or original_height > @max_optimized_height do
        # Resize if too large, maintaining aspect ratio
        # Image.resize/3 signature: resize(image, scale, options)
        # scale is a float scale factor, not width/height
        scale =
          min(@max_optimized_width / original_width, @max_optimized_height / original_height)

        {:ok, resized} = Image.resize(meta_free_image, scale)
        resized
      else
        # Keep original size if within limits
        meta_free_image
      end

    # Write optimized image with quality settings
    write_options = get_write_options(output_format, @optimized_quality)
    Image.write(optimized_image, optimized_output_path, write_options)

    # Create thumbnail (always 500px on longest side)
    {:ok, thumbnail_image} = Image.thumbnail(meta_free_image, @thumbnail_size)
    Image.write(thumbnail_image, thumbnail_output_path, write_options)

    upload_result =
      upload_files_to_s3(
        thumbnail: thumbnail_output_path,
        optimized: optimized_output_path
      )

    # Downscale to very small and generate blurhash
    # Use the optimized image we just created (it's already in temp directory)
    # This ensures we don't create files in the seed directory
    blur_hash = generate_blur_hash_safely(optimized_output_path, path)

    # Use original dimensions for database (not resized dimensions)
    update_processed_image(image, %{
      optimized_image_path: upload_result[:optimized],
      thumbnail_path: upload_result[:thumbnail],
      blur_hash: blur_hash,
      width: original_width,
      height: original_height,
      processing_state: "completed"
    })
  end

  # Detect image format from file extension
  defp detect_image_format(path) do
    ext = Path.extname(path) |> String.downcase()

    case ext do
      ".jpg" -> :jpg
      ".jpeg" -> :jpeg
      ".png" -> :png
      ".webp" -> :webp
      # Default fallback
      _ -> :jpg
    end
  end

  # Determine best output format (WEBP for modern browsers, fallback to original)
  defp determine_output_format(original_format) do
    # Prefer WEBP for better compression, but keep original format for compatibility
    # You can change this to :webp if you want to always convert to WEBP
    case original_format do
      :jpeg -> :jpg
      _ -> original_format
    end
  end

  # Ensure file path has correct extension for the format
  defp ensure_format_extension(path, format) do
    base_path = String.replace(path, ~r/\.[^.]+$/, "")
    extension = format_to_extension(format)
    "#{base_path}#{extension}"
  end

  # Convert format atom to file extension
  defp format_to_extension(format) do
    case format do
      :jpg -> ".jpg"
      :jpeg -> ".jpg"
      :png -> ".png"
      :webp -> ".webp"
      _ -> ".jpg"
    end
  end

  # Get write options based on format
  # Format is determined by file extension, so we mainly need quality settings
  defp get_write_options(_format, quality) do
    [quality: quality]
  end

  def upload_file_to_s3(path) do
    file_name = Path.basename(path)

    path
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(S3Config.bucket_name(), file_name)
    |> ExAws.request!()
  end

  defp upload_files_to_s3(files) do
    Enum.map(files, fn {k, v} ->
      {k, upload_file_to_s3(v)[:body][:location]}
    end)
  end

  # Generate blurhash safely, ensuring we don't create files in source directories
  defp generate_blur_hash_safely(temp_image_path, original_path) do
    # Use the temp image file (optimized_output_path) which is already in /tmp
    # This ensures Blurhash won't create files in the seed directory

    # Generate blurhash from the temp file
    {:ok, blur_hash} =
      Blurhash.downscale_and_encode(temp_image_path, @blur_hash_comp_x, @blur_hash_comp_y)

    # Clean up any PNG file that Blurhash might have created in the original directory
    # (Blurhash.downscale_and_encode may create a temporary PNG file in the source directory)
    original_dir = Path.dirname(original_path)
    original_base = Path.basename(original_path, Path.extname(original_path))
    potential_png = Path.join(original_dir, "#{original_base}.png")

    # Only clean up if the PNG exists and is in a seed/assets directory (to be safe)
    if File.exists?(potential_png) and String.contains?(original_path, "seed/assets") do
      try do
        File.rm(potential_png)
      rescue
        _ -> :ok
      end
    end

    blur_hash
  end
end
