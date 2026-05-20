defmodule ElectricbrainWeb.SettingsLive do
  use ElectricbrainWeb, :live_view

  alias Electricbrain.GoogleCalendar

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Settings")}
  end

  @impl true
  def handle_event("disconnect_google", _params, socket) do
    user = socket.assigns.current_user

    user
    |> Ash.Changeset.for_update(:disconnect_google, %{}, actor: user)
    |> Ash.update!()

    {:noreply,
     socket
     |> assign(:current_user, Ash.reload!(user))
     |> put_flash(:info, "Disconnected Google Calendar")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div>
        <h1 class="font-display text-3xl font-bold tracking-tight text-primary drop-shadow-[0_0_12px_var(--color-primary)]">
          Settings
        </h1>
        <p class="text-sm text-neutral-content/70">
          Connections and preferences.
        </p>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body">
          <h2 class="card-title">Google Calendar</h2>
          <p class="text-sm text-neutral-content/70">
            Push planned items to your Google Calendar's primary calendar. One-way — we never read events back.
          </p>

          <%= if GoogleCalendar.connected?(@current_user) do %>
            <div class="flex items-center gap-3 mt-2">
              <span class="badge badge-success gap-1">
                <.icon name="hero-check-circle-micro" class="size-3.5" /> Connected
              </span>
              <span class="text-sm font-medium">{@current_user.google_email}</span>
              <div class="flex-1"></div>
              <button
                type="button"
                phx-click="disconnect_google"
                data-confirm="Disconnect Google Calendar?"
                class="btn btn-sm btn-ghost text-error"
              >
                Disconnect
              </button>
            </div>
          <% else %>
            <div class="flex items-center gap-3 mt-2">
              <span class="text-sm text-neutral-content/60">Not connected</span>
              <div class="flex-1"></div>
              <.link href={~p"/oauth/google/start"} class="btn btn-sm btn-primary">
                <.icon name="hero-link-micro" class="size-4" /> Connect Google Calendar
              </.link>
            </div>
          <% end %>
        </div>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body">
          <h2 class="card-title">Timezone</h2>
          <p class="text-sm text-neutral-content/70">
            Detected from your browser. Used for week boundaries and calendar display.
          </p>
          <p class="text-sm font-medium mt-2">{@current_user.timezone}</p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
