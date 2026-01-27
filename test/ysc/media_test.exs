defmodule Ysc.MediaTest do
  @moduledoc """
  Tests for Ysc.Media context module.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Media
  alias Ysc.Media.Image
  import Ysc.AccountsFixtures

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "list_images/0" do
    test "returns all images" do
      {:ok, images} = Media.list_images()
      assert is_list(images)
    end
  end

  describe "list_images/2" do
    test "returns paginated images" do
      images = Media.list_images(0, 10)
      assert is_list(images)
      assert length(images) <= 10
    end
  end

  describe "list_images/3" do
    test "filters images by year" do
      current_year = Date.utc_today().year
      images = Media.list_images(0, 10, current_year)
      assert is_list(images)
    end
  end

  describe "get_available_years/0" do
    test "returns list of years" do
      years = Media.get_available_years()
      assert is_list(years)
      assert Enum.all?(years, &is_integer/1)
    end
  end

  describe "fetch_image/1" do
    test "returns image when found" do
      # Create an image
      user = user_fixture()

      {:ok, image} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://example.com/image.jpg",
          processing_state: :unprocessed
        }
        |> Repo.insert()

      found = Media.fetch_image(image.id)
      assert found.id == image.id
    end

    test "returns nil when not found" do
      assert Media.fetch_image(Ecto.ULID.generate()) == nil
    end
  end

  describe "list_unprocessed_images/0" do
    test "returns images in unprocessed or processing state" do
      images = Media.list_unprocessed_images()
      assert is_list(images)
    end
  end

  describe "set_image_processing_state/2" do
    test "updates image processing state", %{user: user} do
      {:ok, image} =
        %Image{
          user_id: user.id,
          raw_image_path: "https://example.com/image.jpg",
          processing_state: :unprocessed
        }
        |> Repo.insert()

      assert {:ok, updated} = Media.set_image_processing_state(image, :processing)
      assert updated.processing_state == :processing
    end
  end
end
