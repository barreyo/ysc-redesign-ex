defmodule Ysc.Media do
  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Media.Image
  alias YscWeb.Authorization.Policy
  alias Ysc.Accounts.User

  def list_images() do
    {:ok, Image |> order_by(desc: :id) |> Repo.all()}
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
    Repo.get(Image, id)
  end

  def add_new_image(attrs, %User{} = current_user) do
    with :ok <- Policy.authorize(:media_image_create, current_user) do
      %Image{}
      |> Image.add_image_changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_image(%Image{} = image, attrs, %User{} = current_user) do
    with :ok <- Policy.authorize(:media_image_update, current_user, image) do
      image
      |> Image.edit_image_changeset(attrs)
      |> Repo.update()
    end
  end

  def delete_image(%Image{} = image, %User{} = current_user) do
    with :ok <- Policy.authorize(:media_image_delete, current_user, image) do
      Repo.delete(image)
    end
  end

  def set_image_processing_state(%Image{} = image, state) do
    Repo.update(Image.image_processing_state_changeset(image, state))
  end

  def update_processed_image(%Image{} = image, attrs) do
    changeset = Image.processed_image_changeset(image, attrs)
    Repo.update!(changeset)
  end
end
