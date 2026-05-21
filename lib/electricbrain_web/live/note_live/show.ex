defmodule ElectricbrainWeb.NoteLive.Show do
  use ElectricbrainWeb, :live_view

  alias Electricbrain.Notes.Note

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    note = Ash.get!(Note, id, actor: user)

    {:ok,
     socket
     |> assign(:page_title, note.title)
     |> assign(:note, note)
     |> assign(:html, render_markdown(note.body || ""))}
  end

  defp render_markdown(body) do
    MDEx.to_html!(body,
      extension: [
        strikethrough: true,
        table: true,
        autolink: true,
        tasklist: true,
        footnotes: true
      ],
      render: [unsafe: false]
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between">
        <.link navigate={~p"/notes"} class="btn btn-sm btn-ghost">
          <.icon name="hero-arrow-left-micro" class="size-4" /> Back
        </.link>
        <.link navigate={~p"/notes/#{@note.id}/edit"} class="btn btn-sm btn-primary">
          <.icon name="hero-pencil-micro" class="size-4" /> Edit
        </.link>
      </div>

      <article class="space-y-6">
        <header>
          <h1 class="text-4xl font-bold tracking-tight text-primary">
            {@note.title}
          </h1>
          <p class="text-xs text-neutral-content/60">
            Updated {Calendar.strftime(@note.updated_at, "%Y-%m-%d %H:%M")}
          </p>
        </header>

        <%= if @note.drawing do %>
          <div
            id={"drawing-view-#{@note.id}"}
            phx-hook="DrawingView"
            data-drawing={Jason.encode!(@note.drawing)}
            class="w-full aspect-[3/2] bg-base-200 border border-base-300 rounded-box"
          >
          </div>
        <% end %>

        <div class="markdown max-w-none">
          {Phoenix.HTML.raw(@html)}
        </div>
      </article>
    </Layouts.app>
    """
  end
end
