defmodule ElectricbrainWeb.NoteLive.Form do
  use ElectricbrainWeb, :live_view

  alias Electricbrain.Notes.ImageStore
  alias Electricbrain.Notes.Images
  alias Electricbrain.Notes.Note
  alias Electricbrain.Notes.NoteBlock

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New note")
    |> assign(:note, nil)
    |> assign(:title, "")
    |> assign(:blocks, [])
    |> assign(:errors, [])
    |> assign(:dirty, false)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = socket.assigns.current_user
    note = Ash.get!(Note, id, actor: user, load: [:blocks])

    blocks =
      note.blocks
      |> Enum.sort_by(& &1.position)
      |> Enum.map(&db_block_to_socket/1)

    socket
    |> assign(:page_title, "Edit note")
    |> assign(:note, note)
    |> assign(:title, note.title)
    |> assign(:blocks, blocks)
    |> assign(:errors, [])
    |> assign(:dirty, false)
  end

  defp db_block_to_socket(block) do
    %{
      client_id: Ecto.UUID.generate(),
      server_id: block.id,
      kind: block.kind,
      data: block.data,
      position: block.position
    }
  end

  @impl true
  def handle_event("form_action", params, socket) do
    action = Map.get(params, "_action", "save")
    socket = merge_params_into_socket(socket, params)

    case action do
      "save" -> save(socket)
      "add_block:markdown" -> {:noreply, socket |> add_block(:markdown) |> mark_dirty()}
      "add_block:excalidraw" -> {:noreply, socket |> add_block(:excalidraw) |> mark_dirty()}
      "add_block:image" -> {:noreply, socket |> add_block(:image) |> mark_dirty()}
      "remove_block:" <> cid -> {:noreply, socket |> remove_block(cid) |> mark_dirty()}
      "move_up:" <> cid -> {:noreply, socket |> move_block(cid, -1) |> mark_dirty()}
      "move_down:" <> cid -> {:noreply, socket |> move_block(cid, +1) |> mark_dirty()}
      _ -> {:noreply, socket}
    end
  end

  defp mark_dirty(socket), do: assign(socket, :dirty, true)

  defp merge_params_into_socket(socket, params) do
    title = Map.get(params, "title", socket.assigns.title)
    order = parse_order(Map.get(params, "block_order", ""))
    submitted = Map.get(params, "blocks", %{})

    existing_by_cid = Map.new(socket.assigns.blocks, &{&1.client_id, &1})

    blocks =
      order
      |> Enum.map(fn cid ->
        existing = Map.get(existing_by_cid, cid)
        submitted_block = Map.get(submitted, cid, %{})
        merge_block(existing, submitted_block)
      end)
      |> Enum.reject(&is_nil/1)

    socket
    |> assign(:title, title)
    |> assign(:blocks, blocks)
  end

  defp parse_order(""), do: []
  defp parse_order(order) when is_binary(order), do: String.split(order, ",", trim: true)
  defp parse_order(_), do: []

  defp merge_block(nil, _), do: nil

  defp merge_block(existing, submitted) do
    data =
      case existing.kind do
        :markdown ->
          %{"body" => Map.get(submitted, "body", existing.data["body"] || "")}

        :excalidraw ->
          snapshot =
            case Jason.decode(Map.get(submitted, "snapshot", "")) do
              {:ok, val} when is_map(val) -> val
              _ -> existing.data["snapshot"] || %{}
            end

          light =
            Map.get(submitted, "preview_svg_light", existing.data["preview_svg_light"] || "")

          dark =
            Map.get(submitted, "preview_svg_dark", existing.data["preview_svg_dark"] || "")

          %{
            "snapshot" => snapshot,
            "preview_svg_light" => light,
            "preview_svg_dark" => dark
          }

        :image ->
          # `upload` is a transient data URL from the JS hook; persisted-key
          # fields ("key", "thumb_key", ...) live in `existing.data` and are
          # rewritten on save (see persist/3).
          upload = Map.get(submitted, "upload", existing.data["upload"] || "")
          alt = Map.get(submitted, "alt", existing.data["alt"] || "")

          existing.data
          |> Map.put("alt", alt)
          |> put_if_present("upload", upload)

        _ ->
          existing.data
      end

    %{existing | data: data}
  end

  defp add_block(socket, kind) do
    new_block = %{
      client_id: Ecto.UUID.generate(),
      server_id: nil,
      kind: kind,
      data: default_data(kind),
      position: length(socket.assigns.blocks)
    }

    assign(socket, :blocks, socket.assigns.blocks ++ [new_block])
  end

  defp default_data(:markdown), do: %{"body" => ""}

  defp default_data(:excalidraw),
    do: %{"snapshot" => %{}, "preview_svg_light" => "", "preview_svg_dark" => ""}

  defp default_data(:image), do: %{"alt" => ""}

  defp put_if_present(map, _key, ""), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp remove_block(socket, cid) do
    blocks = Enum.reject(socket.assigns.blocks, &(&1.client_id == cid))
    assign(socket, :blocks, blocks)
  end

  defp move_block(socket, cid, delta) do
    blocks = socket.assigns.blocks
    idx = Enum.find_index(blocks, &(&1.client_id == cid))
    target = if idx, do: idx + delta, else: nil

    cond do
      is_nil(idx) -> socket
      target < 0 or target >= length(blocks) -> socket
      true -> assign(socket, :blocks, swap(blocks, idx, target))
    end
  end

  defp swap(list, i, j) do
    a = Enum.at(list, i)
    b = Enum.at(list, j)

    list
    |> List.replace_at(i, b)
    |> List.replace_at(j, a)
  end

  defp save(socket) do
    user = socket.assigns.current_user
    title = String.trim(socket.assigns.title || "")

    cond do
      title == "" ->
        {:noreply, assign(socket, :errors, ["Title is required"])}

      true ->
        case persist(socket, user, title) do
          {:ok, _note} ->
            {:noreply,
             socket
             |> put_flash(:info, "Note saved")
             |> push_navigate(to: ~p"/notes")}

          {:error, messages} ->
            {:noreply, assign(socket, :errors, messages)}
        end
    end
  end

  defp persist(socket, user, title) do
    note =
      case socket.assigns.note do
        nil ->
          Note
          |> Ash.Changeset.for_create(:create, %{title: title}, actor: user)
          |> Ash.create!()

        existing ->
          existing
          |> Ash.Changeset.for_update(:update, %{title: title}, actor: user)
          |> Ash.update!()
      end

    blocks = socket.assigns.blocks
    existing_ids = Enum.flat_map(blocks, &if(&1.server_id, do: [&1.server_id], else: []))

    db_blocks_by_id =
      case socket.assigns.note do
        nil ->
          %{}

        _ ->
          (socket.assigns.note.blocks || [])
          |> Map.new(&{&1.id, &1})
      end

    Enum.each(Map.keys(db_blocks_by_id) -- existing_ids, fn id ->
      db_blocks_by_id[id] |> Ash.destroy!(actor: user)
    end)

    blocks
    |> Enum.with_index()
    |> Enum.each(fn {block, idx} ->
      data = prepare_data_for_save(block, note.id)
      attrs = %{position: idx, kind: block.kind, data: data}

      case block.server_id do
        nil ->
          NoteBlock
          |> Ash.Changeset.for_create(:create, Map.put(attrs, :note_id, note.id), actor: user)
          |> Ash.create!()

        id ->
          db_blocks_by_id[id]
          |> Ash.Changeset.for_update(:update, attrs, actor: user)
          |> Ash.update!()
      end
    end)

    {:ok, note}
  rescue
    err in Ash.Error.Invalid ->
      {:error, ash_error_messages(err)}
  end

  # For image blocks, swap the transient data-URL `upload` for the persisted
  # key fields (storing the bytes via Notes.Images). The old key (if any) is
  # deleted to avoid orphans in the bucket.
  defp prepare_data_for_save(%{kind: :image, data: data}, note_id) do
    case Map.get(data, "upload") do
      url when is_binary(url) and url != "" ->
        case Images.put_from_data_url(url, note_id) do
          {:ok, new_fields} ->
            delete_existing_image(data)

            data
            |> Map.drop(["upload"])
            |> Map.merge(new_fields)

          {:error, reason} ->
            raise Ash.Error.Invalid,
              errors: [
                %Ash.Error.Changes.InvalidAttribute{
                  field: :data,
                  message: "image upload failed: #{inspect(reason)}"
                }
              ]
        end

      _ ->
        Map.drop(data, ["upload"])
    end
  end

  defp prepare_data_for_save(%{data: data}, _note_id), do: data

  defp delete_existing_image(%{"key" => key, "thumb_key" => thumb_key} = _data)
       when is_binary(key) and is_binary(thumb_key) and key != "" do
    _ = ImageStore.delete(key)
    _ = ImageStore.delete(thumb_key)
    :ok
  end

  defp delete_existing_image(_), do: :ok

  defp ash_error_messages(%Ash.Error.Invalid{errors: errors}) do
    Enum.map(errors, fn
      %{message: msg} when is_binary(msg) -> msg
      err -> inspect(err)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <.link navigate={~p"/notes"} class="btn btn-sm btn-ghost">
        <.icon name="hero-arrow-left-micro" class="size-4" /> Back
      </.link>

      <h1 class="font-display text-3xl font-bold tracking-tight text-primary">{@page_title}</h1>

      <%= if @errors != [] do %>
        <div class="alert alert-error">
          <ul class="list-disc list-inside">
            <%= for msg <- @errors do %>
              <li>{msg}</li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <div
        id="unsaved-banner"
        class={[
          "fixed bottom-0 inset-x-0 z-40 px-4 py-3 flex items-center justify-between gap-3 border-t border-warning/40 bg-warning text-warning-content shadow-lg",
          if(!@dirty, do: "hidden", else: "")
        ]}
      >
        <span class="text-sm font-medium flex items-center gap-2">
          <.icon name="hero-exclamation-triangle-micro" class="size-4" /> Unsaved changes
        </span>
        <button
          type="submit"
          form="note-form"
          name="_action"
          value="save"
          class="btn btn-sm btn-primary"
        >
          <.icon name="hero-check-micro" class="size-4" /> Save now
        </button>
      </div>

      <form
        id="note-form"
        phx-hook="DirtyForm"
        phx-submit="form_action"
        data-banner="#unsaved-banner"
        class="space-y-6 pb-20"
      >
        <input type="hidden" name="block_order" value={block_order_value(@blocks)} />

        <div>
          <label class="label">
            <span class="label-text">Title</span>
          </label>
          <input
            type="text"
            name="title"
            value={@title}
            class="input input-bordered w-full bg-base-200"
            placeholder="What's on your mind?"
            autocomplete="off"
            required
          />
        </div>

        <div class="space-y-4">
          <%= for {block, idx} <- Enum.with_index(@blocks) do %>
            <.block_editor
              block={block}
              idx={idx}
              total={length(@blocks)}
            />
          <% end %>

          <%= if @blocks == [] do %>
            <p class="text-sm text-neutral-content/60 text-center">
              No blocks yet — add one below.
            </p>
          <% end %>
        </div>

        <div class="flex flex-wrap gap-2 justify-center border-t border-base-300 pt-4">
          <button
            type="submit"
            name="_action"
            value="add_block:markdown"
            class="btn btn-sm btn-ghost"
          >
            <.icon name="hero-document-text-micro" class="size-4" /> Markdown
          </button>
          <button
            type="submit"
            name="_action"
            value="add_block:excalidraw"
            class="btn btn-sm btn-ghost"
          >
            <.icon name="hero-pencil-square-micro" class="size-4" /> Sketch
          </button>
          <button
            type="submit"
            name="_action"
            value="add_block:image"
            class="btn btn-sm btn-ghost"
          >
            <.icon name="hero-photo-micro" class="size-4" /> Image
          </button>
        </div>

        <div class="flex gap-2 justify-end">
          <.link navigate={~p"/notes"} class="btn btn-ghost">Cancel</.link>
          <button type="submit" name="_action" value="save" class="btn btn-primary">
            Save note
          </button>
        </div>
      </form>
    </Layouts.app>
    """
  end

  attr :block, :map, required: true
  attr :idx, :integer, required: true
  attr :total, :integer, required: true

  defp block_editor(assigns) do
    ~H"""
    <div class="card bg-base-200 border border-base-300">
      <div class="card-body p-4 space-y-3">
        <div class="flex items-center justify-between gap-2">
          <span class="text-xs uppercase tracking-wide text-neutral-content/60">
            {block_kind_label(@block.kind)}
          </span>
          <div class="flex gap-1">
            <button
              type="submit"
              name="_action"
              value={"move_up:#{@block.client_id}"}
              class="btn btn-xs btn-ghost"
              disabled={@idx == 0}
              aria-label="Move up"
            >
              <.icon name="hero-arrow-up-micro" class="size-4" />
            </button>
            <button
              type="submit"
              name="_action"
              value={"move_down:#{@block.client_id}"}
              class="btn btn-xs btn-ghost"
              disabled={@idx == @total - 1}
              aria-label="Move down"
            >
              <.icon name="hero-arrow-down-micro" class="size-4" />
            </button>
            <button
              type="submit"
              name="_action"
              value={"remove_block:#{@block.client_id}"}
              class="btn btn-xs btn-ghost text-error"
              aria-label="Remove block"
            >
              <.icon name="hero-trash-micro" class="size-4" />
            </button>
          </div>
        </div>

        <input type="hidden" name={"blocks[#{@block.client_id}][kind]"} value={@block.kind} />
        <input type="hidden" name={"blocks[#{@block.client_id}][client_id]"} value={@block.client_id} />
        <%= if @block.server_id do %>
          <input
            type="hidden"
            name={"blocks[#{@block.client_id}][server_id]"}
            value={@block.server_id}
          />
        <% end %>

        {render_block_body(assigns)}
      </div>
    </div>
    """
  end

  defp render_block_body(%{block: %{kind: :markdown}} = assigns) do
    ~H"""
    <textarea
      name={"blocks[#{@block.client_id}][body]"}
      rows="8"
      class="textarea textarea-bordered w-full font-mono text-sm bg-base-100"
      placeholder="# Heading&#10;&#10;Write in markdown..."
    >{@block.data["body"] || ""}</textarea>
    """
  end

  defp render_block_body(%{block: block} = assigns) when block.kind == :excalidraw do
    cid = block.client_id
    light_svg = block.data["preview_svg_light"] || ""
    dark_svg = block.data["preview_svg_dark"] || ""
    dark_for_render = if dark_svg != "", do: dark_svg, else: light_svg

    assigns =
      assigns
      |> assign(:cid, cid)
      |> assign(:snapshot_input_id, "block-#{cid}-snapshot")
      |> assign(:svg_light_input_id, "block-#{cid}-svg-light")
      |> assign(:svg_dark_input_id, "block-#{cid}-svg-dark")
      |> assign(:preview_light_id, "block-#{cid}-preview-light")
      |> assign(:preview_dark_id, "block-#{cid}-preview-dark")
      |> assign(:overlay_id, "block-#{cid}-overlay")
      |> assign(:editor_id, "block-#{cid}-editor")
      |> assign(:open_btn_id, "block-#{cid}-open")
      |> assign(:close_btn_id, "block-#{cid}-close")
      |> assign(:snapshot_json, Jason.encode!(block.data["snapshot"] || %{}))
      |> assign(:preview_svg_light, light_svg)
      |> assign(:preview_svg_dark, dark_for_render)
      |> assign(:has_preview, light_svg != "")

    ~H"""
    <div class="space-y-2">
      <input
        type="hidden"
        id={@snapshot_input_id}
        name={"blocks[#{@cid}][snapshot]"}
        value={@snapshot_json}
      />
      <input
        type="hidden"
        id={@svg_light_input_id}
        name={"blocks[#{@cid}][preview_svg_light]"}
        value={@preview_svg_light}
      />
      <input
        type="hidden"
        id={@svg_dark_input_id}
        name={"blocks[#{@cid}][preview_svg_dark]"}
        value={@preview_svg_dark}
      />

      <div class="w-full aspect-[3/2] bg-base-100 border border-base-300 rounded-box overflow-hidden relative">
        <div
          id={@preview_light_id}
          class="absolute inset-0 dark:hidden flex items-center justify-center [&>svg]:max-w-full [&>svg]:max-h-full"
        >
          <%= if @has_preview do %>
            {Phoenix.HTML.raw(@preview_svg_light)}
          <% else %>
            <span class="text-sm text-neutral-content/60">
              Empty canvas — tap Open to draw.
            </span>
          <% end %>
        </div>
        <div
          id={@preview_dark_id}
          class="absolute inset-0 hidden dark:flex items-center justify-center [&>svg]:max-w-full [&>svg]:max-h-full"
        >
          <%= if @has_preview do %>
            {Phoenix.HTML.raw(@preview_svg_dark)}
          <% else %>
            <span class="text-sm text-neutral-content/60">
              Empty canvas — tap Open to draw.
            </span>
          <% end %>
        </div>
      </div>

      <div class="flex justify-end">
        <button type="button" id={@open_btn_id} class="btn btn-sm btn-ghost">
          <.icon name="hero-pencil-square-micro" class="size-4" /> Open editor
        </button>
      </div>

      <div
        id={@overlay_id}
        class="fixed inset-0 z-50 bg-base-100 flex-col"
        style="display: none; height: 100dvh;"
      >
        <div class="flex items-center justify-between p-3 border-b border-base-300 bg-base-200">
          <span class="font-semibold">Sketch</span>
          <button type="button" id={@close_btn_id} class="btn btn-sm btn-primary">
            <.icon name="hero-check-micro" class="size-4" /> Done
          </button>
        </div>
        <div
          id={@editor_id}
          phx-hook="ExcalidrawEditor"
          phx-update="ignore"
          data-overlay={"##{@overlay_id}"}
          data-open-button={"##{@open_btn_id}"}
          data-close-button={"##{@close_btn_id}"}
          data-snapshot-input={"##{@snapshot_input_id}"}
          data-svg-light-input={"##{@svg_light_input_id}"}
          data-svg-dark-input={"##{@svg_dark_input_id}"}
          data-preview-light={"##{@preview_light_id}"}
          data-preview-dark={"##{@preview_dark_id}"}
          class="relative flex-1 min-h-0 touch-none"
        >
        </div>
      </div>
    </div>
    """
  end

  defp render_block_body(%{block: block} = assigns) when block.kind == :image do
    cid = block.client_id
    saved_src = saved_image_src(block.data)
    has_saved = saved_src != ""

    assigns =
      assigns
      |> assign(:cid, cid)
      |> assign(:upload_input_id, "block-#{cid}-upload")
      |> assign(:file_input_id, "block-#{cid}-file")
      |> assign(:preview_img_id, "block-#{cid}-preview")
      |> assign(:replace_label_id, "block-#{cid}-replace-label")
      |> assign(:hook_id, "block-#{cid}-image")
      |> assign(:saved_src, saved_src)
      |> assign(:has_saved, has_saved)
      |> assign(:alt, block.data["alt"] || "")

    ~H"""
    <div
      id={@hook_id}
      phx-hook="ImageBlock"
      phx-update="ignore"
      data-upload-input={"##{@upload_input_id}"}
      data-file-input={"##{@file_input_id}"}
      data-preview-img={"##{@preview_img_id}"}
      data-replace-label={"##{@replace_label_id}"}
      class="space-y-2"
    >
      <input
        type="hidden"
        id={@upload_input_id}
        name={"blocks[#{@cid}][upload]"}
        value=""
      />

      <div class="w-full bg-base-100 border border-base-300 rounded-box overflow-hidden flex items-center justify-center min-h-[12rem]">
        <img
          id={@preview_img_id}
          src={@saved_src}
          alt={@alt}
          class={[
            "max-w-full max-h-[60vh] object-contain",
            if(@has_saved, do: "", else: "hidden")
          ]}
        />
        <span
          id={"#{@preview_img_id}-placeholder"}
          class={[
            "text-sm text-neutral-content/60 p-6",
            if(@has_saved, do: "hidden", else: "")
          ]}
        >
          No image yet — choose one below.
        </span>
      </div>

      <div class="flex items-center justify-between gap-2">
        <input
          type="text"
          name={"blocks[#{@cid}][alt]"}
          value={@alt}
          placeholder="Alt text (for accessibility)"
          class="input input-sm input-bordered flex-1 bg-base-200"
        />
        <label
          for={@file_input_id}
          id={@replace_label_id}
          class="btn btn-sm btn-ghost cursor-pointer"
        >
          <.icon name="hero-photo-micro" class="size-4" />
          {if @has_saved, do: "Replace", else: "Choose image"}
        </label>
        <input
          type="file"
          id={@file_input_id}
          accept="image/*"
          class="hidden"
        />
      </div>
    </div>
    """
  end

  defp render_block_body(%{block: block} = assigns) do
    assigns = assign(assigns, :kind, block.kind)

    ~H"""
    <div class="p-3 bg-base-100 border border-error/40 rounded-box text-sm">
      Unsupported block kind <code>{@kind}</code> — remove this block to clean up.
    </div>
    """
  end

  defp saved_image_src(%{"key" => key}) when is_binary(key) and key != "" do
    case ImageStore.presigned_url(key) do
      {:ok, url} -> url
      _ -> ""
    end
  end

  defp saved_image_src(_), do: ""

  defp block_kind_label(:markdown), do: "Markdown"
  defp block_kind_label(:excalidraw), do: "Sketch"
  defp block_kind_label(:image), do: "Image"
  defp block_kind_label(kind), do: to_string(kind)

  defp block_order_value(blocks) do
    blocks |> Enum.map(& &1.client_id) |> Enum.join(",")
  end
end
