defmodule ElectricbrainWeb.SettingsLive do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Devices
  alias Electricbrain.Devices.Pairing
  alias Electricbrain.Devices.PairingCode
  alias Electricbrain.GoogleCalendar
  alias Electricbrain.Notifications.Push
  alias Electricbrain.Notifications.PushSubscription

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:vapid_public_key, vapid_public_key())
     |> assign(:push_environment, nil)
     |> assign(:push_subscriptions, list_subscriptions(user))
     |> assign(:g2_pairings, list_pairings(user))
     |> assign(:g2_pairing_code, current_code(user))}
  end

  defp vapid_public_key do
    Application.get_env(:web_push_elixir, :vapid_public_key)
  end

  defp list_subscriptions(user) do
    PushSubscription
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(actor: user)
  end

  defp list_pairings(user) do
    Pairing
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(actor: user)
  end

  defp current_code(user) do
    now = DateTime.utc_now()

    PairingCode
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(actor: user)
    |> Enum.find(fn c -> DateTime.compare(c.expires_at, now) == :gt end)
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

  def handle_event("enable_push", _params, socket) do
    {:noreply, push_event(socket, "push:request_subscribe", %{})}
  end

  def handle_event(
        "push_environment",
        %{"isIOS" => is_ios, "isStandalone" => standalone, "pushSupported" => supported},
        socket
      ) do
    {:noreply,
     assign(socket, :push_environment, %{
       ios: is_ios,
       standalone: standalone,
       supported: supported
     })}
  end

  def handle_event(
        "save_push_subscription",
        %{
          "endpoint" => endpoint,
          "p256dh_key" => p256dh,
          "auth_key" => auth
        } = params,
        socket
      ) do
    user = socket.assigns.current_user

    case PushSubscription
         |> Ash.Changeset.for_create(
           :create,
           %{
             endpoint: endpoint,
             p256dh_key: p256dh,
             auth_key: auth,
             user_agent: Map.get(params, "user_agent")
           },
           actor: user
         )
         |> Ash.create() do
      {:ok, _sub} ->
        {:noreply,
         socket
         |> assign(:push_subscriptions, list_subscriptions(user))
         |> put_flash(:info, "Notifications enabled on this device.")}

      {:error, _changeset} ->
        # Likely a duplicate endpoint — treat as already-enabled.
        {:noreply,
         socket
         |> assign(:push_subscriptions, list_subscriptions(user))
         |> put_flash(:info, "Notifications already enabled on this device.")}
    end
  end

  def handle_event("push_subscribe_failed", %{"message" => message}, socket) do
    {:noreply, put_flash(socket, :error, "Couldn't enable notifications: #{message}")}
  end

  def handle_event("delete_subscription", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    PushSubscription
    |> Ash.get!(id, actor: user)
    |> Ash.destroy!(actor: user)

    socket =
      socket
      |> assign(:push_subscriptions, list_subscriptions(user))
      |> push_event("push:request_unsubscribe", %{})

    {:noreply, socket}
  end

  def handle_event("set_theme", %{"preference" => pref}, socket)
      when pref in ["system", "light", "dark"] do
    user = socket.assigns.current_user

    updated =
      user
      |> Ash.Changeset.for_update(
        :set_theme_preference,
        %{theme_preference: String.to_existing_atom(pref)},
        actor: user
      )
      |> Ash.update!()

    theme =
      case ElectricbrainWeb.Layouts.theme_attr(updated) do
        false -> nil
        value -> value
      end

    {:noreply,
     socket
     |> assign(:current_user, updated)
     |> push_event("theme:set", %{theme: theme})}
  end

  def handle_event("save_focus_defaults", %{"work_minutes" => w, "break_minutes" => b}, socket) do
    user = socket.assigns.current_user

    with {work, _} <- Integer.parse(to_string(w)),
         {brk, _} <- Integer.parse(to_string(b)) do
      case user
           |> Ash.Changeset.for_update(
             :set_focus_defaults,
             %{focus_work_minutes: work, focus_break_minutes: brk},
             actor: user
           )
           |> Ash.update() do
        {:ok, updated} ->
          {:noreply,
           socket
           |> assign(:current_user, updated)
           |> put_flash(:info, "Focus defaults saved")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Couldn't save those values.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Work and break must be whole numbers.")}
    end
  end

  def handle_event("generate_g2_code", _params, socket) do
    user = socket.assigns.current_user
    code = Devices.generate_code!(user)

    {:noreply,
     socket
     |> assign(:g2_pairing_code, code)
     |> assign(:g2_pairings, list_pairings(user))
     |> put_flash(:info, "Pairing code generated — type it into Trellis on Even Hub.")}
  end

  def handle_event("refresh_g2_pairings", _params, socket) do
    user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(:g2_pairings, list_pairings(user))
     |> assign(:g2_pairing_code, current_code(user))}
  end

  def handle_event("send_g2_test", _params, socket) do
    user = socket.assigns.current_user
    :ok = Devices.send_test_push(user)

    {:noreply,
     put_flash(
       socket,
       :info,
       "Test push sent. Your glasses should wake within a second if connected."
     )}
  end

  def handle_event("delete_g2_pairing", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    Pairing
    |> Ash.get!(id, actor: user)
    |> Ash.destroy!(actor: user)

    {:noreply,
     socket
     |> assign(:g2_pairings, list_pairings(user))
     |> put_flash(:info, "Even Hub device unpaired.")}
  end

  def handle_event("test_push", _params, socket) do
    user = socket.assigns.current_user

    count =
      Push.send_to_user(user, %{
        title: "Trellis",
        body: "Test notification — you're set up.",
        url: "/"
      })

    if count > 0 do
      {:noreply, put_flash(socket, :info, "Test sent to #{count} device(s).")}
    else
      {:noreply,
       put_flash(socket, :error, "No active subscriptions or the push service rejected the send.")}
    end
  end

  defp short_user_agent(nil), do: "Unknown device"

  defp short_user_agent(ua) do
    cond do
      String.contains?(ua, "Firefox") -> "Firefox"
      String.contains?(ua, "Edg/") -> "Edge"
      String.contains?(ua, "Chrome") -> "Chrome"
      String.contains?(ua, "Safari") -> "Safari"
      true -> String.slice(ua, 0, 40)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div>
        <h1 class="font-display text-3xl font-bold tracking-tight text-primary">
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

      <div
        id="push-subscription"
        phx-hook="PushSubscription"
        data-vapid-public-key={@vapid_public_key}
        class="card bg-base-200 border border-base-300"
      >
        <div class="card-body">
          <h2 class="card-title">Notifications</h2>
          <p class="text-sm text-neutral-content/70">
            Get a push 5 minutes before each planned item starts. One subscription per browser — enable on each device you want notified.
          </p>

          <%= cond do %>
            <% is_nil(@vapid_public_key) -> %>
              <div class="alert alert-warning text-xs mt-2">
                VAPID keys not configured on this server. Set <code>VAPID_PUBLIC_KEY</code>
                and <code>VAPID_PRIVATE_KEY</code>
                env vars.
              </div>
            <% match?(%{ios: true, standalone: false, supported: false}, @push_environment) -> %>
              <div class="alert alert-info text-xs mt-2">
                <div>
                  <p class="font-semibold mb-1">iOS requires installing this app first</p>
                  <p>
                    Tap the share icon <span class="inline-block px-1">⎙</span>
                    in Safari, then "Add to Home Screen". Open the installed icon and come back here to enable notifications.
                  </p>
                </div>
              </div>
            <% match?(%{supported: false}, @push_environment) -> %>
              <div class="alert alert-warning text-xs mt-2">
                Push notifications aren't supported in this browser.
              </div>
            <% true -> %>
              <div class="flex flex-wrap items-center gap-2 mt-2">
                <button type="button" phx-click="enable_push" class="btn btn-sm btn-primary">
                  <.icon name="hero-bell-micro" class="size-4" /> Enable on this device
                </button>
                <button
                  :if={@push_subscriptions != []}
                  type="button"
                  phx-click="test_push"
                  class="btn btn-sm btn-ghost"
                >
                  <.icon name="hero-paper-airplane-micro" class="size-4" /> Send test
                </button>
              </div>
          <% end %>

          <%= if @vapid_public_key && @push_subscriptions != [] do %>
            <ul class="mt-3 space-y-1">
              <%= for sub <- @push_subscriptions do %>
                <li class="flex items-center gap-3 py-1.5 px-2 rounded hover:bg-base-300/40 text-sm">
                  <.icon
                    name="hero-device-phone-mobile-micro"
                    class="size-4 text-neutral-content/60"
                  />
                  <span class="font-medium">{short_user_agent(sub.user_agent)}</span>
                  <span class="text-xs text-neutral-content/60">
                    added {Calendar.strftime(
                      DateTime.shift_zone!(sub.inserted_at, @current_user.timezone || "Etc/UTC"),
                      "%Y-%m-%d"
                    )}
                  </span>
                  <div class="flex-1"></div>
                  <button
                    type="button"
                    phx-click="delete_subscription"
                    phx-value-id={sub.id}
                    data-confirm="Disable notifications on this device?"
                    class="btn btn-xs btn-ghost text-error"
                  >
                    <.icon name="hero-x-mark-micro" class="size-4" />
                  </button>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body">
          <h2 class="card-title">Even Hub glasses</h2>
          <p class="text-sm text-neutral-content/70">
            Surface your now / next entry, live focus countdown, and today's
            habits on Even Realities G2 glasses via the Trellis Even Hub plugin.
            Pair one phone per pair of glasses.
          </p>

          <%= if @g2_pairing_code do %>
            <div class="mt-3 rounded border border-base-300 bg-base-100 p-3">
              <p class="text-xs text-neutral-content/70 mb-1">Pairing code (10-min expiry)</p>
              <p class="font-mono text-2xl tracking-[0.4em] font-semibold">
                {@g2_pairing_code.code}
              </p>
              <p class="text-xs text-neutral-content/60 mt-1">
                Open the Trellis plugin on Even Hub and enter this code.
              </p>
              <button
                type="button"
                phx-click="refresh_g2_pairings"
                class="btn btn-xs btn-ghost mt-2"
              >
                <.icon name="hero-arrow-path-micro" class="size-3.5" /> I've entered it
              </button>
            </div>
          <% else %>
            <div class="flex flex-wrap items-center gap-2 mt-2">
              <button type="button" phx-click="generate_g2_code" class="btn btn-sm btn-primary">
                <.icon name="hero-key-micro" class="size-4" /> Pair Even Hub plugin
              </button>
            </div>
          <% end %>

          <%= if @g2_pairings != [] do %>
            <ul class="mt-3 space-y-1">
              <%= for p <- @g2_pairings do %>
                <li class="flex items-center gap-3 py-1.5 px-2 rounded hover:bg-base-300/40 text-sm">
                  <.icon name="hero-eye-micro" class="size-4 text-neutral-content/60" />
                  <span class="font-medium">{p.label}</span>
                  <span class="text-xs text-neutral-content/60">
                    <%= if p.last_seen_at do %>
                      last seen {Calendar.strftime(
                        DateTime.shift_zone!(p.last_seen_at, @current_user.timezone || "Etc/UTC"),
                        "%Y-%m-%d %H:%M"
                      )}
                    <% else %>
                      paired, awaiting first request
                    <% end %>
                  </span>
                  <div class="flex-1"></div>
                  <button
                    type="button"
                    phx-click="delete_g2_pairing"
                    phx-value-id={p.id}
                    data-confirm="Unpair this device?"
                    class="btn btn-xs btn-ghost text-error"
                  >
                    <.icon name="hero-x-mark-micro" class="size-4" />
                  </button>
                </li>
              <% end %>
            </ul>

            <div class="mt-3 pt-3 border-t border-base-300">
              <button
                type="button"
                phx-click="send_g2_test"
                class="btn btn-xs btn-ghost"
              >
                <.icon name="hero-paper-airplane-micro" class="size-3.5" /> Send test to glasses
              </button>
              <span class="text-xs text-neutral-content/60 ml-2">
                Wakes the HUD via the SSE stream — independent of the Notifications card,
                which targets your browser.
              </span>
            </div>
          <% end %>
        </div>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body">
          <h2 class="card-title">Theme</h2>
          <p class="text-sm text-neutral-content/70">
            Follow your device, or pin a single theme. The page updates as soon as you choose.
          </p>
          <div class="join mt-2">
            <%= for {value, label} <- [{"system", "System"}, {"light", "Light"}, {"dark", "Dark"}] do %>
              <button
                type="button"
                phx-click="set_theme"
                phx-value-preference={value}
                class={[
                  "join-item btn btn-sm",
                  if(to_string(@current_user.theme_preference) == value,
                    do: "btn-primary",
                    else: "btn-ghost"
                  )
                ]}
              >
                {label}
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body">
          <h2 class="card-title">Focus</h2>
          <p class="text-sm text-neutral-content/70">
            Defaults for the pomodoro timer. Each session snapshots these
            at start time, so changing them here only affects future sessions.
          </p>
          <form
            phx-submit="save_focus_defaults"
            class="grid grid-cols-2 gap-3 mt-2 max-w-sm"
          >
            <label class="text-sm">
              <span class="text-xs text-neutral-content/60">Work (minutes)</span>
              <input
                type="number"
                name="work_minutes"
                value={@current_user.focus_work_minutes}
                min="1"
                max="240"
                class="input input-sm input-bordered w-full bg-base-100"
              />
            </label>
            <label class="text-sm">
              <span class="text-xs text-neutral-content/60">Break (minutes)</span>
              <input
                type="number"
                name="break_minutes"
                value={@current_user.focus_break_minutes}
                min="0"
                max="60"
                class="input input-sm input-bordered w-full bg-base-100"
              />
            </label>
            <div class="col-span-2">
              <button type="submit" class="btn btn-sm btn-primary">
                Save defaults
              </button>
            </div>
          </form>
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
