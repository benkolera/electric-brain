defmodule ElectricbrainWeb.SettingsLive do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.GoogleCalendar
  alias Electricbrain.Notifications.Push
  alias Electricbrain.Notifications.PushSubscription

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:vapid_public_key, vapid_public_key())
     |> assign(:push_subscriptions, list_subscriptions(socket.assigns.current_user))}
  end

  defp vapid_public_key do
    Application.get_env(:web_push_elixir, :vapid_public_key)
  end

  defp list_subscriptions(user) do
    PushSubscription
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(actor: user)
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

  def handle_event("test_push", _params, socket) do
    user = socket.assigns.current_user

    count =
      Push.send_to_user(user, %{
        title: "Electric Brain",
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

          <%= if is_nil(@vapid_public_key) do %>
            <div class="alert alert-warning text-xs mt-2">
              VAPID keys not configured on this server. Set <code>VAPID_PUBLIC_KEY</code>
              and <code>VAPID_PRIVATE_KEY</code>
              env vars.
            </div>
          <% else %>
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

            <%= if @push_subscriptions == [] do %>
              <p class="text-xs text-neutral-content/60 mt-2">
                No devices subscribed yet.
              </p>
            <% else %>
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
