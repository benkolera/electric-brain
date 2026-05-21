defmodule ElectricbrainWeb.NoteLiveTest do
  use ElectricbrainWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  require Ash.Query

  alias Electricbrain.Notes.Note
  alias Electricbrain.Notes.NoteBlock

  setup %{conn: conn} do
    user = create_user!()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  defp create_note!(user, title) do
    Note
    |> Ash.Changeset.for_create(:create, %{title: title}, actor: user)
    |> Ash.create!()
  end

  defp create_block!(user, attrs) do
    NoteBlock
    |> Ash.Changeset.for_create(:create, attrs, actor: user)
    |> Ash.create!()
  end

  defp blocks_for(user, note_id) do
    NoteBlock
    |> Ash.Query.filter(note_id == ^note_id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(actor: user)
  end

  describe "index" do
    test "lists notes with first-markdown preview", %{conn: conn, user: user} do
      note = create_note!(user, "Plans")

      create_block!(user, %{
        note_id: note.id,
        kind: :markdown,
        data: %{"body" => "Things to do"},
        position: 0
      })

      {:ok, _view, html} = live(conn, ~p"/notes")
      assert html =~ "Plans"
      assert html =~ "Things to do"
    end

    test "shows (sketch) preview when only a sketch block exists", %{conn: conn, user: user} do
      note = create_note!(user, "Doodle")

      create_block!(user, %{
        note_id: note.id,
        kind: :sketch,
        data: %{"drawing" => %{"strokes" => []}},
        position: 0
      })

      {:ok, _view, html} = live(conn, ~p"/notes")
      assert html =~ "Doodle"
      assert html =~ "(sketch)"
    end
  end

  describe "new" do
    test "saving a note with no blocks persists just the title", %{conn: conn, user: user} do
      {:ok, view, _} = live(conn, ~p"/notes/new")

      view
      |> form("#note-form", %{"title" => "Skeletal"})
      |> render_submit(%{"_action" => "save"})

      assert [n] = Ash.read!(Note, actor: user, load: [:blocks])
      assert n.title == "Skeletal"
      assert n.blocks == []
    end

    test "Add Markdown button appends a block to the form", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/notes/new")

      html =
        view
        |> form("#note-form", %{"title" => "Draft"})
        |> render_submit(%{"_action" => "add_block:markdown"})

      assert html =~ "Markdown"
      assert html =~ ~s|name="blocks[|
    end

    test "save persists added markdown block", %{conn: conn, user: user} do
      {:ok, view, _} = live(conn, ~p"/notes/new")

      view
      |> form("#note-form", %{"title" => "x"})
      |> render_submit(%{"_action" => "add_block:markdown"})

      html = render(view)
      cid = Regex.run(~r/blocks\[([a-f0-9-]+)\]\[kind\]/, html) |> Enum.at(1)

      view
      |> form("#note-form", %{
        "title" => "With body",
        "block_order" => cid,
        "blocks" => %{cid => %{"body" => "hello world"}}
      })
      |> render_submit(%{"_action" => "save"})

      assert [note] = Ash.read!(Note, actor: user, load: [:blocks])
      assert note.title == "With body"
      assert [block] = note.blocks
      assert block.kind == :markdown
      assert block.data["body"] == "hello world"
      assert block.position == 0
    end
  end

  describe "edit" do
    test "loads existing blocks", %{conn: conn, user: user} do
      note = create_note!(user, "Existing")

      create_block!(user, %{
        note_id: note.id,
        kind: :markdown,
        data: %{"body" => "older content"},
        position: 0
      })

      {:ok, _view, html} = live(conn, ~p"/notes/#{note.id}/edit")
      assert html =~ "Existing"
      assert html =~ "older content"
    end

    test "reorders blocks via move_down then saves", %{conn: conn, user: user} do
      note = create_note!(user, "Reorder me")

      _a =
        create_block!(user, %{
          note_id: note.id,
          kind: :markdown,
          data: %{"body" => "alpha"},
          position: 0
        })

      _b =
        create_block!(user, %{
          note_id: note.id,
          kind: :markdown,
          data: %{"body" => "beta"},
          position: 1
        })

      {:ok, view, html} = live(conn, ~p"/notes/#{note.id}/edit")

      [cid_a, cid_b] =
        Regex.scan(~r/blocks\[([a-f0-9-]+)\]\[kind\]/, html) |> Enum.map(&Enum.at(&1, 1))

      view
      |> form("#note-form", %{
        "title" => "Reorder me",
        "block_order" => "#{cid_a},#{cid_b}",
        "blocks" => %{
          cid_a => %{"body" => "alpha"},
          cid_b => %{"body" => "beta"}
        }
      })
      |> render_submit(%{"_action" => "move_down:#{cid_a}"})

      view
      |> form("#note-form", %{
        "title" => "Reorder me",
        "block_order" => "#{cid_b},#{cid_a}",
        "blocks" => %{
          cid_a => %{"body" => "alpha"},
          cid_b => %{"body" => "beta"}
        }
      })
      |> render_submit(%{"_action" => "save"})

      bodies = blocks_for(user, note.id) |> Enum.map(& &1.data["body"])
      assert bodies == ["beta", "alpha"]
    end

    test "removing a block destroys it on save", %{conn: conn, user: user} do
      note = create_note!(user, "Trim")

      keep =
        create_block!(user, %{
          note_id: note.id,
          kind: :markdown,
          data: %{"body" => "keep"},
          position: 0
        })

      _drop =
        create_block!(user, %{
          note_id: note.id,
          kind: :markdown,
          data: %{"body" => "drop"},
          position: 1
        })

      {:ok, view, html} = live(conn, ~p"/notes/#{note.id}/edit")

      [_cid_keep, cid_drop] =
        Regex.scan(~r/blocks\[([a-f0-9-]+)\]\[kind\]/, html) |> Enum.map(&Enum.at(&1, 1))

      [cid_keep, cid_drop2] =
        Regex.scan(~r/blocks\[([a-f0-9-]+)\]\[kind\]/, html) |> Enum.map(&Enum.at(&1, 1))

      assert cid_drop2 == cid_drop

      view
      |> form("#note-form", %{
        "title" => "Trim",
        "block_order" => "#{cid_keep},#{cid_drop}",
        "blocks" => %{
          cid_keep => %{"body" => "keep"},
          cid_drop => %{"body" => "drop"}
        }
      })
      |> render_submit(%{"_action" => "remove_block:#{cid_drop}"})

      html2 = render(view)
      cids = Regex.scan(~r/blocks\[([a-f0-9-]+)\]\[kind\]/, html2) |> Enum.map(&Enum.at(&1, 1))
      assert length(cids) == 1
      [cid_remaining] = cids
      assert cid_remaining == cid_keep
      _ = keep

      view
      |> form("#note-form", %{
        "title" => "Trim",
        "block_order" => cid_remaining,
        "blocks" => %{
          cid_remaining => %{"body" => "keep"}
        }
      })
      |> render_submit(%{"_action" => "save"})

      bodies = blocks_for(user, note.id) |> Enum.map(& &1.data["body"])
      assert bodies == ["keep"]
    end
  end

  describe "show" do
    test "renders markdown then sketch in order", %{conn: conn, user: user} do
      note = create_note!(user, "Display")

      create_block!(user, %{
        note_id: note.id,
        kind: :markdown,
        data: %{"body" => "# Heading"},
        position: 0
      })

      create_block!(user, %{
        note_id: note.id,
        kind: :sketch,
        data: %{"drawing" => %{"strokes" => []}},
        position: 1
      })

      {:ok, _view, html} = live(conn, ~p"/notes/#{note.id}")
      assert html =~ "<h1>Heading</h1>"
      assert html =~ ~s|phx-hook="DrawingView"|
    end
  end
end
