defmodule ElectricbrainWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ElectricbrainWeb, :html

  import ElectricbrainWeb.AgendaHelpers

  embed_templates "layouts/*"

  @doc """
  Returns the `data-theme` value for the current user, or `false` to omit the
  attribute (which lets daisyUI's `prefersdark` follow the OS preference).
  """
  def theme_attr(%{theme_preference: :light}), do: "electricbrain-light"
  def theme_attr(%{theme_preference: :dark}), do: "electricbrain-dark"
  def theme_attr(_), do: false

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :map, default: nil
  attr :now_agenda, :map, default: %{current: [], next: nil}

  attr :wide, :boolean,
    default: false,
    doc:
      "drop the page's max-width — for pages like the planner that benefit from a 3-column desktop layout"

  attr :show_pause_fab, :boolean,
    default: true,
    doc:
      "show the floating Pause button. Hidden on pages where the page itself IS the pause (/moments/new)."

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-base-100 text-base-content">
      <%= if @current_user do %>
        <div id="timezone-detect" phx-hook="TimezoneDetect" phx-update="ignore"></div>
      <% end %>
      <header class="navbar sticky top-0 z-40 bg-base-200/60 backdrop-blur border-b border-base-300 px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <a href="/" class="flex items-center gap-2 group">
            <img
              src={~p"/images/trellis-logo-256.png"}
              alt="Trellis"
              class="size-9 transition"
            />
            <span class="font-display text-lg font-bold tracking-tight text-primary transition">
              Trellis
            </span>
          </a>
        </div>
        <div class="flex-none">
          <%= if @current_user do %>
            <ul class="hidden lg:flex menu menu-horizontal items-center gap-1 px-1">
              <.nav_items current_user={@current_user} />
            </ul>

            <details class="dropdown dropdown-end lg:hidden">
              <summary
                class="btn btn-ghost btn-square"
                aria-label="Open menu"
              >
                <.icon name="hero-bars-3-micro" class="size-6" />
              </summary>
              <ul class="dropdown-content menu bg-base-200 rounded-box mt-2 min-w-56 shadow-lg z-50 p-2 gap-1 border border-base-300">
                <.nav_items current_user={@current_user} />
              </ul>
            </details>
          <% else %>
            <ul class="menu menu-horizontal items-center gap-1 px-1">
              <li>
                <.link navigate={~p"/sign-in"} class="btn btn-sm btn-ghost">Sign in</.link>
              </li>
              <li>
                <.link navigate={~p"/register"} class="btn btn-sm btn-primary">Register</.link>
              </li>
            </ul>
          <% end %>
        </div>
      </header>

      <.now_banner
        :if={@current_user}
        now_agenda={@now_agenda}
        timezone={@current_user.timezone || "Etc/UTC"}
      />

      <main class="flex-1 px-4 py-8 pb-24 sm:px-6 lg:px-8">
        <div class={["mx-auto space-y-6", if(@wide, do: "max-w-none", else: "max-w-5xl")]}>
          {render_slot(@inner_block)}
        </div>
      </main>

      <.link
        :if={@current_user && @show_pause_fab}
        navigate={~p"/moments/new"}
        class="fixed bottom-5 right-5 z-30 btn btn-accent btn-circle shadow-lg size-14"
        title="Pause — sit with a craving, urge or feeling"
        aria-label="Pause"
      >
        <.icon name="hero-pause-circle" class="size-7" />
      </.link>

      <.live_component
        :if={@current_user}
        module={ElectricbrainWeb.FocusLive.Widget}
        id="focus-widget"
        current_user={@current_user}
        focus_session={assigns[:focus_session]}
      />

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :current_user, :map, required: true

  defp nav_items(assigns) do
    ~H"""
    <li>
      <.link navigate={~p"/plan"} class="font-medium">
        <.icon name="hero-calendar-days-micro" class="size-4" /> Plan
      </.link>
    </li>
    <li>
      <.link navigate={~p"/categories"} class="font-medium">
        <.icon name="hero-rectangle-stack-micro" class="size-4" /> Categories
      </.link>
    </li>
    <li>
      <.link navigate={~p"/notes"} class="font-medium">
        <.icon name="hero-document-text-micro" class="size-4" /> Notes
      </.link>
    </li>
    <li>
      <.link navigate={~p"/todos"} class="font-medium">
        <.icon name="hero-check-circle-micro" class="size-4" /> Todos
      </.link>
    </li>
    <li>
      <.link navigate={~p"/habits"} class="font-medium">
        <.icon name="hero-arrow-path-micro" class="size-4" /> Habits
      </.link>
    </li>
    <li>
      <.link navigate={~p"/time-blocks"} class="font-medium">
        <.icon name="hero-clock-micro" class="size-4" /> Time blocks
      </.link>
    </li>
    <li>
      <.link navigate={~p"/metrics"} class="font-medium">
        <.icon name="hero-chart-bar-micro" class="size-4" /> Metrics
      </.link>
    </li>
    <li>
      <.link navigate={~p"/ingredients"} class="font-medium">
        <.icon name="hero-cake-micro" class="size-4" /> Ingredients
      </.link>
    </li>
    <li>
      <.link navigate={~p"/moments"} class="font-medium">
        <.icon name="hero-pause-circle-micro" class="size-4" /> Moments
      </.link>
    </li>
    <li>
      <.link navigate={~p"/focus"} class="font-medium">
        <.icon name="hero-clock-micro" class="size-4" /> Focus
      </.link>
    </li>
    <li>
      <.link navigate={~p"/help"} class="font-medium">
        <.icon name="hero-question-mark-circle-micro" class="size-4" /> Help
      </.link>
    </li>
    <li>
      <.link navigate={~p"/settings"} class="font-medium">
        <.icon name="hero-cog-6-tooth-micro" class="size-4" /> Settings
      </.link>
    </li>
    <li>
      <.link
        href={~p"/sign-out"}
        method="delete"
        class="font-medium text-neutral-content/70 whitespace-nowrap"
      >
        <.icon name="hero-arrow-right-on-rectangle-micro" class="size-4" /> Sign out
      </.link>
    </li>
    """
  end

  attr :now_agenda, :map, required: true
  attr :timezone, :string, required: true

  def now_banner(assigns) do
    assigns =
      assign(assigns,
        items: assigns.now_agenda[:current] || [],
        next: assigns.now_agenda[:next]
      )

    ~H"""
    <div :if={@items != [] or @next} class="border-b border-base-300 bg-base-200/60">
      <div class="mx-auto max-w-5xl px-4 sm:px-6 lg:px-8 py-2 flex flex-col gap-1">
        <div :for={item <- @items} class="flex items-center gap-3 text-sm">
          <span class="inline-flex items-center gap-1 font-semibold text-accent">
            <span class="size-2 rounded-full bg-accent animate-pulse"></span> Now
          </span>
          <span class="font-medium truncate">{item_title(item)}</span>
          <span class="font-mono text-xs text-neutral-content/60">
            {format_time_range(item, @timezone)}
          </span>
          <span class="badge badge-ghost badge-sm font-mono">
            {format_hhmm(minutes_remaining(item))} left
          </span>
        </div>
        <div :if={@items == [] and @next} class="flex items-center gap-3 text-sm">
          <span class="text-neutral-content/60">Up next</span>
          <span class="font-medium truncate">{item_title(@next)}</span>
          <span class="font-mono text-xs text-neutral-content/60">
            at {format_clock(@next.entry.planned_at, @timezone)} · in {format_hhmm(
              minutes_until(@next)
            )}
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
