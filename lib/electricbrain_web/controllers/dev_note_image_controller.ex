defmodule ElectricbrainWeb.DevNoteImageController do
  @moduledoc """
  Serves note image bytes from the in-process `ImageStore.Memory` adapter so
  the browser can render images in dev without S3. Mounted only when the
  Memory adapter is configured (i.e. when `NOTES_BUCKET` is unset). Returns
  404 for any other adapter — prod uses presigned S3 URLs directly.

  Authorization is "any authenticated user" — Memory is single-process and
  dev/test is single-user. Don't reuse this controller in prod.
  """

  use ElectricbrainWeb, :controller

  alias Electricbrain.Notes.ImageStore.Memory

  def show(conn, %{"key" => key_parts}) when is_list(key_parts) do
    key = Enum.join(key_parts, "/")

    case Memory.fetch(key) do
      %{binary: binary, content_type: content_type} ->
        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(200, binary)

      _ ->
        send_resp(conn, 404, "")
    end
  end
end
