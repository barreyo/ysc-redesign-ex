defmodule Ysc.Media do
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Media
  alias Ysc.S3Config
  alias YscWeb.Authorization.Policy
  alias Ysc.Accounts.User

  @blur_hash_comp_x 4
  @blur_hash_comp_y 3
  @thumbnail_size 500

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
    blur_hash = generate_blur_hash(path)

    update_processed_image(image, %{
      optimized_image_path: upload_result[:optimized],
      thumbnail_path: upload_result[:thumbnail],
      blur_hash: blur_hash,
      width: width,
      height: height,
      processing_state: "completed"
    })
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

  defp generate_blur_hash(path) do
    {:ok, blur_hash} = Blurhash.downscale_and_encode(path, @blur_hash_comp_x, @blur_hash_comp_y)
    blur_hash
  end
end
