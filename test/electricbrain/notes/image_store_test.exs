defmodule Electricbrain.Notes.ImageStoreTest do
  use ExUnit.Case, async: false

  alias Electricbrain.Notes.ImageStore
  alias Electricbrain.Notes.ImageStore.Memory

  setup do
    Memory.reset()
    :ok
  end

  test "put/3 stores the binary and content_type under the given key" do
    :ok = ImageStore.put("notes/abc/img.jpg", "JFIF...", "image/jpeg")

    assert %{binary: "JFIF...", content_type: "image/jpeg"} =
             Memory.fetch("notes/abc/img.jpg")
  end

  test "presigned_url/1 returns a stable url for a key (Memory adapter is deterministic)" do
    assert {:ok, "/dev/notes-images/notes/abc/img.jpg"} =
             ImageStore.presigned_url("notes/abc/img.jpg")
  end

  test "delete/1 removes the stored object" do
    :ok = ImageStore.put("notes/abc/img.jpg", "data", "image/jpeg")
    :ok = ImageStore.delete("notes/abc/img.jpg")

    assert Memory.fetch("notes/abc/img.jpg") == nil
  end

  test "put/3 over an existing key overwrites" do
    :ok = ImageStore.put("k", "v1", "image/jpeg")
    :ok = ImageStore.put("k", "v2", "image/png")

    assert %{binary: "v2", content_type: "image/png"} = Memory.fetch("k")
  end
end
