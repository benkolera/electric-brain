defmodule ElectricbrainWeb.NoteLive.Index do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Notes
  alias Electricbrain.Notes.Note

  @impl true
  def mount(_params, _session, socket) do
    notes = list_notes(socket.assigns.current_user)
    {:ok, assign(socket, notes: notes, page_title: "Notes")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    Note
    |> Ash.get!(id, actor: user)
    |> Ash.destroy!(actor: user)

    {:noreply, assign(socket, notes: list_notes(user))}
  end

  defp list_notes(user) do
    Note
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load(:blocks)
    |> Ash.read!(actor: user, domain: Notes)
  end

  defp note_preview(note) do
    blocks = note.blocks || []

    case Enum.find(blocks, &(&1.kind == :markdown)) do
      nil ->
        if Enum.any?(blocks, &(&1.kind == :excalidraw)), do: "(sketch)", else: ""

      block ->
        block.data |> Map.get("body", "") |> String.slice(0, 200)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-primary">Notes</h1>
          <p class="text-sm text-neutral-content/70">Markdown thoughts with optional sketches.</p>
        </div>
        <.link navigate={~p"/notes/new"} class="btn btn-primary">
          <.icon name="hero-plus-micro" class="size-4" /> New note
        </.link>
      </div>

      <div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for note <- @notes do %>
          <div class="card bg-base-200 border border-base-300 hover:border-primary/60 transition">
            <div class="card-body">
              <h3 class="card-title">
                <.link navigate={~p"/notes/#{note.id}"} class="link link-hover">
                  {note.title}
                </.link>
              </h3>
              <p class="text-sm text-neutral-content/70 line-clamp-3 whitespace-pre-wrap">
                {note_preview(note)}
              </p>
              <div class="card-actions justify-end mt-2">
                <.link navigate={~p"/notes/#{note.id}/edit"} class="btn btn-xs btn-ghost">
                  Edit
                </.link>
                <button
                  phx-click="delete"
                  phx-value-id={note.id}
                  data-confirm="Delete this note?"
                  class="btn btn-xs btn-ghost text-error"
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        <% end %>
        <%= if @notes == [] do %>
          <div class="col-span-full text-center py-12 text-neutral-content/60">
            No notes yet — start your second brain.
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
