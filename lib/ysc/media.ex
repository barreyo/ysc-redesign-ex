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
    IO.puts("💾 [Media] update_processed_image called")

    IO.inspect(
      %{
        image_id: image.id,
        attrs: attrs
      },
      label: "Update processed image input"
    )

    changeset = Media.Image.processed_image_changeset(image, attrs)
    IO.puts("💾 [Media] Changeset created:")

    IO.inspect(
      %{
        valid?: changeset.valid?,
        changes: changeset.changes,
        errors: changeset.errors
      },
      label: "Changeset details"
    )

    if not changeset.valid? do
      IO.puts("❌ [Media] Changeset is invalid!")
      IO.inspect(changeset.errors, label: "Changeset errors")
    end

    result = Repo.update!(changeset)
    IO.puts("💾 [Media] Database update completed:")

    IO.inspect(
      %{
        id: result.id,
        optimized_image_path: result.optimized_image_path,
        thumbnail_path: result.thumbnail_path,
        processing_state: result.processing_state
      },
      label: "Updated image from DB"
    )

    result
  end

  def process_image_upload(
        %Media.Image{} = image,
        path,
        thumbnail_output_path,
        optimized_output_path
      ) do
    IO.puts("🔵 [Media] Starting process_image_upload")

    IO.inspect(
      %{
        image_id: image.id,
        original_path: path,
        thumbnail_output_path: thumbnail_output_path,
        optimized_output_path: optimized_output_path
      },
      label: "Input parameters"
    )

    {:ok, parsed_image} = Image.open(path)
    {:ok, meta_free_image} = Image.remove_metadata(parsed_image)

    # Get original dimensions
    original_width = Image.width(parsed_image)
    original_height = Image.height(parsed_image)
    IO.puts("📐 [Media] Original dimensions: #{original_width}x#{original_height}")

    # Detect original format from file extension
    original_format = detect_image_format(path)
    IO.puts("🎨 [Media] Original format: #{inspect(original_format)}")

    # Determine output format - prefer WEBP for better compression, fallback to original format
    output_format = determine_output_format(original_format)
    IO.puts("🎨 [Media] Output format: #{inspect(output_format)}")

    # Ensure optimized output path uses correct extension
    optimized_output_path = ensure_format_extension(optimized_output_path, output_format)
    thumbnail_output_path = ensure_format_extension(thumbnail_output_path, output_format)
    IO.puts("📁 [Media] Final paths:")

    IO.inspect(
      %{
        optimized_output_path: optimized_output_path,
        thumbnail_output_path: thumbnail_output_path
      },
      label: "Final output paths"
    )

    # Create optimized version: maintain aspect ratio, cap at max dimensions, preserve quality
    optimized_image =
      if original_width > @max_optimized_width or original_height > @max_optimized_height do
        IO.puts("🔄 [Media] Resizing image (exceeds max dimensions)")
        # Resize if too large, maintaining aspect ratio
        # Image.resize/3 signature: resize(image, scale, options)
        # scale is a float scale factor, not width/height
        scale =
          min(@max_optimized_width / original_width, @max_optimized_height / original_height)

        IO.puts("📏 [Media] Resize scale: #{scale}")
        {:ok, resized} = Image.resize(meta_free_image, scale)
        resized
      else
        IO.puts("✅ [Media] Image within size limits, keeping original size")
        # Keep original size if within limits
        meta_free_image
      end

    # Write optimized image with quality settings
    write_options = get_write_options(output_format, @optimized_quality)
    IO.puts("💾 [Media] Writing optimized image to: #{optimized_output_path}")
    write_result = Image.write(optimized_image, optimized_output_path, write_options)
    IO.inspect(write_result, label: "Optimized image write result")

    optimized_file_exists = File.exists?(optimized_output_path)

    optimized_file_size =
      if optimized_file_exists, do: File.stat!(optimized_output_path).size, else: 0

    IO.puts(
      "✅ [Media] Optimized file exists: #{optimized_file_exists}, size: #{optimized_file_size} bytes"
    )

    # Create thumbnail (always 500px on longest side)
    {:ok, thumbnail_image} = Image.thumbnail(meta_free_image, @thumbnail_size)
    IO.puts("💾 [Media] Writing thumbnail to: #{thumbnail_output_path}")
    thumbnail_write_result = Image.write(thumbnail_image, thumbnail_output_path, write_options)
    IO.inspect(thumbnail_write_result, label: "Thumbnail write result")

    thumbnail_file_exists = File.exists?(thumbnail_output_path)

    thumbnail_file_size =
      if thumbnail_file_exists, do: File.stat!(thumbnail_output_path).size, else: 0

    IO.puts(
      "✅ [Media] Thumbnail file exists: #{thumbnail_file_exists}, size: #{thumbnail_file_size} bytes"
    )

    IO.puts("☁️ [Media] Starting S3 uploads...")

    upload_result =
      upload_files_to_s3(
        thumbnail: thumbnail_output_path,
        optimized: optimized_output_path
      )

    IO.puts("☁️ [Media] S3 upload result:")
    IO.inspect(upload_result, label: "Upload result")

    # Downscale to very small and generate blurhash
    # Use the optimized image we just created (it's already in temp directory)
    # This ensures we don't create files in the seed directory
    IO.puts("🎨 [Media] Generating blurhash...")
    blur_hash = generate_blur_hash_safely(optimized_output_path, path)
    IO.puts("✅ [Media] Blurhash generated: #{String.slice(blur_hash, 0, 20)}...")

    # Use original dimensions for database (not resized dimensions)
    update_attrs = %{
      optimized_image_path: upload_result[:optimized],
      thumbnail_path: upload_result[:thumbnail],
      blur_hash: blur_hash,
      width: original_width,
      height: original_height,
      processing_state: "completed"
    }

    IO.puts("💾 [Media] Preparing database update with attrs:")
    IO.inspect(update_attrs, label: "Update attrs")

    IO.puts("💾 [Media] Current image state before update:")

    IO.inspect(
      %{
        id: image.id,
        optimized_image_path: image.optimized_image_path,
        thumbnail_path: image.thumbnail_path,
        processing_state: image.processing_state
      },
      label: "Current image state"
    )

    result = update_processed_image(image, update_attrs)
    IO.puts("✅ [Media] Database update result:")
    IO.inspect(result, label: "Update result")

    IO.puts("💾 [Media] Image state after update:")

    IO.inspect(
      %{
        id: result.id,
        optimized_image_path: result.optimized_image_path,
        thumbnail_path: result.thumbnail_path,
        processing_state: result.processing_state
      },
      label: "Updated image state"
    )

    IO.puts("🔵 [Media] Finished process_image_upload")
    result
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
    bucket_name = S3Config.bucket_name()

    IO.puts("☁️ [Media] upload_file_to_s3 called")

    IO.inspect(
      %{
        path: path,
        file_name: file_name,
        bucket_name: bucket_name,
        file_exists: File.exists?(path),
        file_size: if(File.exists?(path), do: File.stat!(path).size, else: 0)
      },
      label: "Upload file details"
    )

    result =
      path
      |> ExAws.S3.Upload.stream_file()
      |> ExAws.S3.upload(bucket_name, file_name)
      |> ExAws.request!()

    IO.puts("☁️ [Media] upload_file_to_s3 result:")
    IO.inspect(result, label: "Upload request result")

    location = result[:body][:location]
    IO.puts("☁️ [Media] Upload location: #{inspect(location)}")

    result
  end

  defp upload_files_to_s3(files) do
    IO.puts("☁️ [Media] upload_files_to_s3 called with files:")
    IO.inspect(files, label: "Files to upload")

    result =
      Enum.map(files, fn {k, v} ->
        IO.puts("☁️ [Media] Uploading #{k}: #{v}")
        upload_response = upload_file_to_s3(v)
        IO.puts("☁️ [Media] Upload response for #{k}:")
        IO.inspect(upload_response, label: "Upload response")

        location = upload_response[:body][:location]
        IO.puts("☁️ [Media] Extracted location for #{k}: #{inspect(location)}")
        {k, location}
      end)
      |> Enum.into(%{})

    IO.puts("☁️ [Media] upload_files_to_s3 final result:")
    IO.inspect(result, label: "Final upload result")

    result
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
