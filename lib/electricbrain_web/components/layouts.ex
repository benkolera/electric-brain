defmodule ElectricbrainWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ElectricbrainWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :map, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-base-100 text-base-content">
      <%= if @current_user do %>
        <div id="timezone-detect" phx-hook="TimezoneDetect" phx-update="ignore"></div>
      <% end %>
      <header class="navbar bg-base-200/60 backdrop-blur border-b border-base-300 px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <a href="/" class="flex items-center gap-2 group">
            <img
              src={~p"/images/brain-logo-256.png"}
              alt="Electric Brain"
              class="size-9 rounded-lg group-hover:drop-shadow-[0_0_12px_var(--color-primary)] transition"
            />
            <span class="font-display text-lg font-bold tracking-tight text-primary group-hover:drop-shadow-[0_0_8px_var(--color-primary)] transition">
              Electric Brain
            </span>
          </a>
        </div>
        <div class="flex-none">
          <ul class="menu menu-horizontal items-center gap-1 px-1">
            <%= if @current_user do %>
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
                <details>
                  <summary class="font-medium text-neutral-content/80">
                    {@current_user.email}
                  </summary>
                  <ul class="bg-base-200 rounded-box right-0 min-w-40 z-10">
                    <li>
                      <.link navigate={~p"/settings"}>
                        <.icon name="hero-cog-6-tooth-micro" class="size-4" /> Settings
                      </.link>
                    </li>
                    <li>
                      <.link href={~p"/sign-out"} method="delete">
                        <.icon name="hero-arrow-right-on-rectangle-micro" class="size-4" /> Sign out
                      </.link>
                    </li>
                  </ul>
                </details>
              </li>
            <% else %>
              <li>
                <.link navigate={~p"/sign-in"} class="btn btn-sm btn-ghost">Sign in</.link>
              </li>
              <li>
                <.link navigate={~p"/register"} class="btn btn-sm btn-primary">Register</.link>
              </li>
            <% end %>
          </ul>
        </div>
      </header>

      <main class="flex-1 px-4 py-8 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-5xl space-y-6">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
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
