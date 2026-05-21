defmodule Electricbrain.Notes.Images do
  @moduledoc """
  Server-side image processing for note image blocks. Inputs are the data
  URLs the browser hook produces (already client-side downscaled to ~1600px
  JPEG). We decode them, derive a thumbnail via libvips, and hand the bytes
  to `ImageStore`.
  """

  alias Electricbrain.Notes.ImageStore

  @thumb_max_edge 400
  @main_prefix "notes"

  @doc """
  Decode `data_url`, write the original and a thumbnail to `ImageStore` under
  `note_id`, and return the persisted shape to store in the block's `data`
  jsonb. Errors bubble back as `{:error, reason}`.
  """
  def put_from_data_url(data_url, note_id) when is_binary(data_url) and is_binary(note_id) do
    with {:ok, {mime_type, binary}} <- decode_data_url(data_url),
         {:ok, img} <- Image.open(binary, access: :random),
         {:ok, thumb} <- thumbnail(img),
         {:ok, thumb_jpeg} <- to_jpeg(thumb) do
      uuid = Ecto.UUID.generate()
      key = "#{@main_prefix}/#{note_id}/#{uuid}.jpg"
      thumb_key = "#{@main_prefix}/#{note_id}/#{uuid}.thumb.jpg"

      with :ok <- ImageStore.put(key, binary, mime_type),
           :ok <- ImageStore.put(thumb_key, thumb_jpeg, "image/jpeg") do
        {:ok,
         %{
           "key" => key,
           "thumb_key" => thumb_key,
           "mime_type" => mime_type,
           "width" => Image.width(img),
           "height" => Image.height(img)
         }}
      end
    end
  end

  @doc "Delete a stored image and its thumbnail. Soft-fails on individual errors."
  def delete(%{"key" => key, "thumb_key" => thumb_key}) do
    if is_binary(key) and key != "", do: ImageStore.delete(key)
    if is_binary(thumb_key) and thumb_key != "", do: ImageStore.delete(thumb_key)
    :ok
  end

  def delete(_), do: :ok

  defp decode_data_url("data:" <> rest) do
    case String.split(rest, ",", parts: 2) do
      [meta, b64] ->
        mime_type = meta |> String.split(";") |> List.first()

        case Base.decode64(b64) do
          {:ok, binary} -> {:ok, {mime_type, binary}}
          :error -> {:error, :invalid_base64}
        end

      _ ->
        {:error, :invalid_data_url}
    end
  end

  defp decode_data_url(_), do: {:error, :invalid_data_url}

  defp thumbnail(img) do
    Image.thumbnail(img, "#{@thumb_max_edge}", crop: :none)
  end

  defp to_jpeg(img) do
    Image.write(img, :memory, suffix: ".jpg", quality: 85)
  end
end
