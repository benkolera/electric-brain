defmodule Electricbrain.Notes.ImageStore.S3 do
  @moduledoc """
  S3 `ImageStore` adapter. Reads `:bucket`, `:region`, and `:presign_ttl` from
  `Application.get_env(:electricbrain, :notes_image_store)`. AWS credentials
  come from the default chain (ECS task role in prod, `~/.aws/credentials` or
  env vars locally).
  """

  @behaviour Electricbrain.Notes.ImageStore

  @impl true
  def put(key, binary, content_type) do
    bucket()
    |> ExAws.S3.put_object(key, binary, content_type: content_type)
    |> request()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def presigned_url(key) do
    config = ExAws.Config.new(:s3, region: region())
    ExAws.S3.presigned_url(config, :get, bucket(), key, expires_in: presign_ttl())
  end

  @impl true
  def delete(key) do
    bucket()
    |> ExAws.S3.delete_object(key)
    |> request()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp request(op), do: ExAws.request(op, region: region())

  defp bucket do
    config!() |> Keyword.fetch!(:bucket)
  end

  defp region do
    config!() |> Keyword.fetch!(:region)
  end

  defp presign_ttl do
    config!() |> Keyword.get(:presign_ttl, 3600)
  end

  defp config! do
    Application.get_env(:electricbrain, :notes_image_store) ||
      raise """
      ImageStore.S3 is configured as the adapter but
      `:electricbrain, :notes_image_store` is not set. Expected
      `[bucket: ..., region: ..., presign_ttl: ...]`.
      """
  end
end
