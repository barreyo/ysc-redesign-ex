defmodule YscWeb.TrixUploadsController do
  alias Ysc.Accounts.User
  alias Ysc.Media
  use YscWeb, :controller

  @bucket_name "media"
  @temp_dir "/tmp/image_processor"

  def create(conn, params) do
    IO.puts("GAME")
    IO.inspect(params)
    IO.inspect(conn.assigns[:current_user])
    IO.puts("DANCE")

    res = upload_file(params, conn.assigns[:current_user])

    send_resp(conn, 201, res)
  end

  defp upload_file(
         %{"file" => %Plug.Upload{}} = plug_upload,
         %User{} = current_user
       ) do
    # 1. Upload raw file to s3
    # 2. Insert DB entry
    # 3. Run the image processor task and await the results
    # 4. Return optimized url or raw url

    IO.inspect(plug_upload)
    tmp_path = plug_upload["file"].path

    upload_result = Media.upload_file_to_s3(tmp_path)
    raw_s3_path = upload_result[:body][:location]

    {:ok, new_image} =
      Media.add_new_image(
        %{
          raw_image_path: URI.encode(raw_s3_path),
          user_id: current_user.id
        },
        current_user
      )

    make_temp_dir(@temp_dir)
    tmp_output_file = "#{@temp_dir}/#{new_image.id}"
    optimized_output_path = "#{tmp_output_file}_optimized.png"
    thumbnail_output_path = "#{tmp_output_file}_thumb.png"

    updated_image =
      Media.process_image_upload(
        new_image,
        tmp_path,
        thumbnail_output_path,
        optimized_output_path
      )

    get_return_url(updated_image)
  end

  defp get_return_url(%Media.Image{optimized_image_path: nil} = image), do: image.raw_image_path
  defp get_return_url(%Media.Image{optimized_image_path: optimized_path}), do: optimized_path

  defp ext(content_type) do
    [ext | _] = MIME.extensions(content_type)
    ext
  end

  defp make_temp_dir(path) do
    File.mkdir(path)
  end
end
