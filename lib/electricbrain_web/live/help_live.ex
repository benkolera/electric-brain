defmodule ElectricbrainWeb.HelpLive do
  use ElectricbrainWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Help")
     |> assign(:html, render_markdown(read_help()))}
  end

  defp read_help do
    path = Application.app_dir(:electricbrain, "priv/help/index.md")

    case File.read(path) do
      {:ok, body} -> body
      {:error, _} -> "Help content not found."
    end
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
      <div>
        <h1 class="font-display text-3xl font-bold tracking-tight text-primary">
          Help
        </h1>
        <p class="text-sm text-neutral-content/70">
          How Trellis is meant to be used, and how the pieces link.
        </p>
      </div>

      <article class="markdown max-w-none">
        {Phoenix.HTML.raw(@html)}
      </article>
    </Layouts.app>
    """
  end
end
