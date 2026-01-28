defmodule YscWeb.TrixUploadsControllerTest do
  use YscWeb.ConnCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Posts

  setup %{conn: conn} do
    user = user_fixture(%{role: :admin})
    conn = log_in_user(conn, user)
    %{conn: conn, user: user}
  end

  describe "create/2" do
    @tag :skip
    test "uploads file and returns URL", %{conn: conn, user: user} do
      # This test requires S3 configuration (localstack or real S3)
      # Skip by default as it requires external service setup
      # To run: mix test --include skip test/ysc_web/controllers/trix_uploads_controller_test.exs

      # Create a test image file
      {:ok, post} =
        Posts.create_post(
          %{
            "title" => "Test Post",
            "body" => "Body",
            "url_name" => "test-post"
          },
          user
        )

      # Create a minimal test image file
      test_image_path = "/tmp/test_image_#{System.unique_integer([:positive])}.jpg"
      File.write!(test_image_path, <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46>>)

      upload = %Plug.Upload{
        path: test_image_path,
        filename: "test.jpg",
        content_type: "image/jpeg"
      }

      # Mock the S3 upload and image processing
      # Note: This test requires S3 to be configured (localstack or real S3)
      conn =
        conn
        |> put_req_header("content-type", "multipart/form-data")
        |> post(~p"/admin/trix-uploads", %{
          "post_id" => post.id,
          "file" => upload
        })

      # The controller should return 201 with a URL
      # Actual implementation may vary, so we check for success status
      assert response(conn, 201) || response(conn, 200)
    end
  end
end
