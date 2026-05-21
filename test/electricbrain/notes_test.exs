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

    test "creates a sketch block with drawing", %{user: user} do
      note = create_note!(user)
      drawing = %{"strokes" => [%{"color" => "#fff", "points" => [[0, 0], [1, 1]]}]}

      block =
        create_block!(user, %{
          note_id: note.id,
          kind: :sketch,
          data: %{"drawing" => drawing},
          position: 1
        })

      assert block.kind == :sketch
      assert get_in(block.data, ["drawing", "strokes"]) |> length() == 1
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

    test "rejects sketch without :drawing", %{user: user} do
      note = create_note!(user)

      assert {:error, _} =
               NoteBlock
               |> Ash.Changeset.for_create(
                 :create,
                 %{note_id: note.id, kind: :sketch, data: %{}, position: 0},
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
               |> Ash.Changeset.for_update(:update, %{kind: :sketch, data: %{"body" => "ok"}},
                 actor: user
               )
               |> Ash.update()
    end
  end
end
