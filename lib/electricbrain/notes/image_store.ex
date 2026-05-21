defmodule Electricbrain.Notes.ImageStore do
  @moduledoc """
  Storage abstraction for note image blocks. Two adapters today:

    * `ImageStore.S3` — production / staging; uses the default AWS credential
      chain so the ECS task role (or `~/.aws/credentials` locally) supplies
      credentials. Configured via `:electricbrain, :notes_image_store`
      `{:bucket, :region, :presign_ttl}`.

    * `ImageStore.Memory` — tests and the default dev path when no bucket is
      configured. Agent-backed, holds blobs in-process.

  The block's `data` jsonb stores only opaque keys — never URLs, since
  presigned URLs expire. URLs are regenerated at render time via
  `presigned_url/1`.
  """

  @type key :: String.t()
  @type content_type :: String.t()

  @callback put(key, binary(), content_type) :: :ok | {:error, term()}
  @callback presigned_url(key) :: {:ok, String.t()} | {:error, term()}
  @callback delete(key) :: :ok | {:error, term()}

  @spec put(key, binary(), content_type) :: :ok | {:error, term()}
  def put(key, binary, content_type), do: adapter().put(key, binary, content_type)

  @spec presigned_url(key) :: {:ok, String.t()} | {:error, term()}
  def presigned_url(key), do: adapter().presigned_url(key)

  @spec delete(key) :: :ok | {:error, term()}
  def delete(key), do: adapter().delete(key)

  defp adapter do
    Application.get_env(
      :electricbrain,
      :notes_image_store_adapter,
      Electricbrain.Notes.ImageStore.Memory
    )
  end
end
