defmodule Electricbrain.Notes.ImageStore.Memory do
  @moduledoc """
  In-memory `ImageStore` adapter backed by an Agent. Used by tests and by dev
  when `NOTES_BUCKET` is unset. Exposes `fetch/1` so tests can assert what
  was written without going through S3.
  """

  @behaviour Electricbrain.Notes.ImageStore

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @impl true
  def put(key, binary, content_type)
      when is_binary(key) and is_binary(binary) and is_binary(content_type) do
    Agent.update(__MODULE__, &Map.put(&1, key, %{binary: binary, content_type: content_type}))
  end

  @impl true
  def presigned_url(key) when is_binary(key) do
    # The Phoenix router mounts a dev-only controller at this path that
    # streams bytes back out of this Agent. The browser fetches over HTTP
    # like it would for an S3 presigned URL.
    {:ok, "/dev/notes-images/" <> key}
  end

  @impl true
  def delete(key) when is_binary(key) do
    Agent.update(__MODULE__, &Map.delete(&1, key))
  end

  @doc "Test helper: returns `%{binary, content_type}` for a key, or nil."
  def fetch(key) when is_binary(key) do
    Agent.get(__MODULE__, &Map.get(&1, key))
  end

  @doc "Test helper: drop every stored object. Call in setup."
  def reset do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end
end
