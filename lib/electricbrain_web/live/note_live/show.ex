defmodule ElectricbrainWeb.NoteLive.Show do
  use ElectricbrainWeb, :live_view

  alias Electricbrain.Notes.Note

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    note = Ash.get!(Note, id, actor: user, load: [:blocks])

    {:ok,
     socket
     |> assign(:page_title, note.title)
     |> assign(:note, note)}
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

        <%= if @note.blocks == [] do %>
          <p class="text-sm text-neutral-content/60 italic">
            This note has no blocks yet — edit to add some.
          </p>
        <% end %>

        <%= for block <- @note.blocks do %>
          {render_block(assigns, block)}
        <% end %>
      </article>
    </Layouts.app>
    """
  end

  defp render_block(assigns, %{kind: :markdown} = block) do
    assigns = assign(assigns, :html, ElectricbrainWeb.Markdown.to_html(block.data["body"] || ""))

    ~H"""
    <div class="markdown max-w-none">
      {Phoenix.HTML.raw(@html)}
    </div>
    """
  end

  defp render_block(assigns, %{kind: :excalidraw} = block) do
    assigns =
      assigns
      |> assign(:block_id, block.id)
      |> assign(:preview_svg, block.data["preview_svg"] || "")

    ~H"""
    <div
      id={"excalidraw-view-#{@block_id}"}
      class="w-full aspect-[3/2] bg-base-200 border border-base-300 rounded-box overflow-hidden flex items-center justify-center [&>svg]:max-w-full [&>svg]:max-h-full"
    >
      <%= if @preview_svg != "" do %>
        {Phoenix.HTML.raw(@preview_svg)}
      <% else %>
        <span class="text-sm text-neutral-content/60">Empty sketch</span>
      <% end %>
    </div>
    """
  end

  defp render_block(assigns, block) do
    assigns = assign(assigns, :kind, block.kind)

    ~H"""
    <div class="p-3 bg-base-100 border border-error/40 rounded-box text-sm">
      Unsupported block kind <code>{@kind}</code>.
    </div>
    """
  end
end
