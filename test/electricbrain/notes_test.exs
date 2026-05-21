defmodule Electricbrain.NotesTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Notes.Note
  alias Electricbrain.Notes.NoteBlock

  setup do
    user = create_user!()
    {:ok, user: user}
  end

  defp create_note!(user, title \\ "A note") do
    Note
    |> Ash.Changeset.for_create(:create, %{title: title}, actor: user)
    |> Ash.create!()
  end

  defp create_block!(user, attrs) do
    NoteBlock
    |> Ash.Changeset.for_create(:create, attrs, actor: user)
    |> Ash.create!()
  end

  describe "Note" do
    test "creates a note without blocks", %{user: user} do
      note = create_note!(user, "Empty")
      assert note.title == "Empty"
      assert note.user_id == user.id

      reloaded = Ash.get!(Note, note.id, actor: user, load: [:blocks])
      assert reloaded.blocks == []
    end

    test "destroying a note cascades to blocks", %{user: user} do
      note = create_note!(user)

      create_block!(user, %{
        note_id: note.id,
        kind: :markdown,
        data: %{"body" => "x"},
        position: 0
      })

      Ash.destroy!(note, actor: user)
      assert Ash.read!(NoteBlock, actor: user) == []
    end
  end

  describe "NoteBlock create" do
    test "creates a markdown block with body", %{user: user} do
      note = create_note!(user)

      block =
        create_block!(user, %{
          note_id: note.id,
          kind: :markdown,
          data: %{"body" => "Hello"},
          position: 0
        })

      assert block.kind == :markdown
      assert block.data == %{"body" => "Hello"}
      assert block.position == 0
    end

    test "creates an excalidraw block with snapshot + light/dark previews", %{user: user} do
      note = create_note!(user)

      block =
        create_block!(user, %{
          note_id: note.id,
          kind: :excalidraw,
          data: %{
            "snapshot" => %{"elements" => []},
            "preview_svg_light" => "<svg id='light'></svg>",
            "preview_svg_dark" => "<svg id='dark'></svg>"
          },
          position: 1
        })

      assert block.kind == :excalidraw
      assert block.data["preview_svg_light"] == "<svg id='light'></svg>"
      assert block.data["preview_svg_dark"] == "<svg id='dark'></svg>"
    end

    test "creates an image block with key/thumb_key/mime_type", %{user: user} do
      note = create_note!(user)

      block =
        create_block!(user, %{
          note_id: note.id,
          kind: :image,
          data: %{
            "key" => "notes/#{note.id}/abc.jpg",
            "thumb_key" => "notes/#{note.id}/abc.thumb.jpg",
            "mime_type" => "image/jpeg",
            "width" => 800,
            "height" => 600,
            "alt" => "a photo"
          },
          position: 2
        })

      assert block.kind == :image
      assert block.data["key"] == "notes/#{note.id}/abc.jpg"
      assert block.data["thumb_key"] == "notes/#{note.id}/abc.thumb.jpg"
      assert block.data["alt"] == "a photo"
    end

    test "rejects image block missing required keys", %{user: user} do
      note = create_note!(user)

      assert {:error, _} =
               NoteBlock
               |> Ash.Changeset.for_create(
                 :create,
                 %{note_id: note.id, kind: :image, data: %{"alt" => "no key"}, position: 0},
                 actor: user
               )
               |> Ash.create()

      assert {:error, _} =
               NoteBlock
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   note_id: note.id,
                   kind: :image,
                   data: %{"key" => "k", "thumb_key" => ""},
                   position: 0
                 },
                 actor: user
               )
               |> Ash.create()
    end

    test "destroying an image block deletes its bytes from ImageStore", %{user: user} do
      alias Electricbrain.Notes.ImageStore
      alias Electricbrain.Notes.ImageStore.Memory

      Memory.reset()
      note = create_note!(user)

      key = "notes/#{note.id}/img.jpg"
      thumb = "notes/#{note.id}/img.thumb.jpg"
      :ok = ImageStore.put(key, "MAIN", "image/jpeg")
      :ok = ImageStore.put(thumb, "THUMB", "image/jpeg")

      block =
        create_block!(user, %{
          note_id: note.id,
          kind: :image,
          data: %{
            "key" => key,
            "thumb_key" => thumb,
            "mime_type" => "image/jpeg",
            "width" => 10,
            "height" => 10
          },
          position: 0
        })

      Ash.destroy!(block, actor: user)

      assert Memory.fetch(key) == nil
      assert Memory.fetch(thumb) == nil
    end

    test "rejects an unknown kind", %{user: user} do
      note = create_note!(user)

      assert {:error, _} =
               NoteBlock
               |> Ash.Changeset.for_create(
                 :create,
                 %{note_id: note.id, kind: :video, data: %{}, position: 0},
                 actor: user
               )
               |> Ash.create()
    end

    test "rejects markdown without :body", %{user: user} do
      note = create_note!(user)

      assert {:error, _} =
               NoteBlock
               |> Ash.Changeset.for_create(
                 :create,
                 %{note_id: note.id, kind: :markdown, data: %{}, position: 0},
                 actor: user
               )
               |> Ash.create()
    end

    test "rejects excalidraw missing required keys", %{user: user} do
      note = create_note!(user)

      assert {:error, _} =
               NoteBlock
               |> Ash.Changeset.for_create(
                 :create,
                 %{note_id: note.id, kind: :excalidraw, data: %{}, position: 0},
                 actor: user
               )
               |> Ash.create()

      assert {:error, _} =
               NoteBlock
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   note_id: note.id,
                   kind: :excalidraw,
                   data: %{"snapshot" => %{}, "preview_svg_light" => ""},
                   position: 0
                 },
                 actor: user
               )
               |> Ash.create()
    end

    test "blocks load sorted by position", %{user: user} do
      note = create_note!(user)

      create_block!(user, %{
        note_id: note.id,
        kind: :markdown,
        data: %{"body" => "second"},
        position: 1
      })

      create_block!(user, %{
        note_id: note.id,
        kind: :markdown,
        data: %{"body" => "first"},
        position: 0
      })

      reloaded = Ash.get!(Note, note.id, actor: user, load: [:blocks])
      bodies = Enum.map(reloaded.blocks, & &1.data["body"])
      assert bodies == ["first", "second"]
    end

    test "cannot attach to another user's note", %{user: user} do
      other = create_user!()
      other_note = create_note!(other)

      assert {:error, _} =
               NoteBlock
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   note_id: other_note.id,
                   kind: :markdown,
                   data: %{"body" => "stealth"},
                   position: 0
                 },
                 actor: user
               )
               |> Ash.create()
    end
  end

  describe "NoteBlock update" do
    test "rejects a swap to invalid data shape", %{user: user} do
      note = create_note!(user)

      block =
        create_block!(user, %{
          note_id: note.id,
          kind: :markdown,
          data: %{"body" => "ok"},
          position: 0
        })

      assert {:error, _} =
               block
               |> Ash.Changeset.for_update(:update, %{kind: :excalidraw, data: %{"body" => "ok"}},
                 actor: user
               )
               |> Ash.update()
    end
  end
end
