defmodule ElectricbrainWeb.NoteLive.Form do
  use ElectricbrainWeb, :live_view

  alias Electricbrain.Notes.Note

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    form =
      Note
      |> AshPhoenix.Form.for_create(:create, actor: socket.assigns.current_user)
      |> to_form()

    socket
    |> assign(:page_title, "New note")
    |> assign(:note, nil)
    |> assign(:form, form)
    |> assign(:drawing_json, "null")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = socket.assigns.current_user
    note = Ash.get!(Note, id, actor: user)

    form =
      note
      |> AshPhoenix.Form.for_update(:update, actor: user)
      |> to_form()

    socket
    |> assign(:page_title, "Edit note")
    |> assign(:note, note)
    |> assign(:form, form)
    |> assign(:drawing_json, Jason.encode!(note.drawing))
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params, "drawing" => drawing}, socket) do
    drawing_map =
      case Jason.decode(drawing) do
        {:ok, val} when is_map(val) -> val
        _ -> nil
      end

    params = Map.put(params, "drawing", drawing_map)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _note} ->
        {:noreply,
         socket
         |> put_flash(:info, "Note saved")
         |> push_navigate(to: ~p"/notes")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.link navigate={~p"/notes"} class="btn btn-sm btn-ghost">
        <.icon name="hero-arrow-left-micro" class="size-4" /> Back
      </.link>

      <h1 class="font-display text-3xl font-bold tracking-tight text-primary">{@page_title}</h1>

      <.form
        for={@form}
        id="note-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <input type="hidden" name="drawing" id="drawing-input" value={@drawing_json} />

        <div>
          <label class="label">
            <span class="label-text">Title</span>
          </label>
          <input
            type="text"
            name={@form[:title].name}
            value={Phoenix.HTML.Form.normalize_value("text", @form[:title].value)}
            class="input input-bordered w-full bg-base-200"
            placeholder="What's on your mind?"
            autocomplete="off"
            required
          />
          <%= for {msg, _} <- @form[:title].errors do %>
            <p class="text-error text-sm mt-1">{msg}</p>
          <% end %>
        </div>

        <div>
          <label class="label">
            <span class="label-text">Body (Markdown)</span>
          </label>
          <textarea
            name={@form[:body].name}
            rows="10"
            class="textarea textarea-bordered w-full font-mono text-sm bg-base-200"
            placeholder="# Heading\n\nWrite anything in markdown..."
          >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>
        </div>

        <div>
          <label class="label flex items-center justify-between">
            <span class="label-text">Sketch</span>
            <button type="button" class="btn btn-xs btn-ghost" id="clear-canvas-btn">
              <.icon name="hero-trash-micro" class="size-4" /> Clear
            </button>
          </label>
          <div
            id="drawing-canvas"
            phx-hook="DrawingCanvas"
            phx-update="ignore"
            data-target="#drawing-input"
            data-initial={@drawing_json}
            class="w-full aspect-[3/2] bg-base-200 border border-base-300 rounded-box touch-none"
          >
          </div>
          <p class="text-xs text-neutral-content/60 mt-1">
            Tap and drag to sketch. Touch-friendly on phones and tablets.
          </p>
        </div>

        <div class="flex gap-2 justify-end">
          <.link navigate={~p"/notes"} class="btn btn-ghost">Cancel</.link>
          <button type="submit" class="btn btn-primary">Save note</button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
