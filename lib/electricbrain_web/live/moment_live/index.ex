defmodule ElectricbrainWeb.MomentLive.Index do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Moments.Moment

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    categories = Electricbrain.Categories.list_with_paths(user)

    {:ok,
     socket
     |> assign(:page_title, "Moments")
     |> assign(:categories_by_id, Map.new(categories, &{&1.id, &1}))
     |> assign(:kind_filter, :all)
     |> assign(:moments, list_moments(user, :all))}
  end

  defp list_moments(user, :all) do
    Moment
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(actor: user)
  end

  defp list_moments(user, kind) when is_atom(kind) do
    Moment
    |> Ash.Query.filter(kind == ^kind)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(actor: user)
  end

  @impl true
  def handle_event("filter_kind", %{"kind" => raw}, socket) do
    user = socket.assigns.current_user

    kind =
      case raw do
        "all" -> :all
        s -> String.to_existing_atom(s)
      end

    {:noreply,
     socket
     |> assign(:kind_filter, kind)
     |> assign(:moments, list_moments(user, kind))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    Moment
    |> Ash.get!(id, actor: user)
    |> Ash.destroy!(actor: user)

    {:noreply, assign(socket, :moments, list_moments(user, socket.assigns.kind_filter))}
  end

  defp kind_label(:craving), do: "Craving"
  defp kind_label(:urge), do: "Urge"
  defp kind_label(:feeling), do: "Feeling"
  defp kind_label(:other), do: "Other"

  defp kind_color(:craving), do: "badge-warning"
  defp kind_color(:urge), do: "badge-accent"
  defp kind_color(:feeling), do: "badge-info"
  defp kind_color(:other), do: "badge-ghost"

  defp format_relative(dt, tz) do
    tz = tz || "Etc/UTC"
    local = DateTime.shift_zone!(dt, tz)
    now_local = DateTime.utc_now() |> DateTime.shift_zone!(tz)
    diff_seconds = DateTime.diff(now_local, local, :second)

    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 7 * 86_400 -> "#{div(diff_seconds, 86_400)}d ago"
      true -> Calendar.strftime(local, "%Y-%m-%d %H:%M")
    end
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :current, :any, required: true

  defp filter_chip(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="filter_kind"
      phx-value-kind={to_string(@value)}
      class={[
        "btn btn-xs",
        if(@current == @value, do: "btn-primary", else: "btn-outline")
      ]}
    >
      {@label}
    </button>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-accent drop-shadow-[0_0_12px_var(--color-accent)]">
            Moments
          </h1>
          <p class="text-sm text-neutral-content/70">
            Cravings, urges, feelings you've sat with.
          </p>
        </div>
        <.link navigate={~p"/moments/new"} class="btn btn-primary">
          <.icon name="hero-pause-circle-micro" class="size-4" /> Pause
        </.link>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <span class="text-xs text-neutral-content/60">Filter:</span>
        <.filter_chip label="All" value={:all} current={@kind_filter} />
        <.filter_chip label="Cravings" value={:craving} current={@kind_filter} />
        <.filter_chip label="Urges" value={:urge} current={@kind_filter} />
        <.filter_chip label="Feelings" value={:feeling} current={@kind_filter} />
        <.filter_chip label="Other" value={:other} current={@kind_filter} />
      </div>

      <%= if @moments == [] do %>
        <div class="text-center py-12 text-neutral-content/60">
          <%= if @kind_filter == :all do %>
            No moments yet. <.link navigate={~p"/moments/new"} class="link link-primary">Pause</.link>
            when something pulls.
          <% else %>
            No moments of this kind.
          <% end %>
        </div>
      <% else %>
        <ul class="space-y-2">
          <%= for m <- @moments do %>
            <li class="flex items-center gap-3 p-3 bg-base-200 border border-base-300 rounded-box">
              <.link navigate={~p"/moments/#{m.id}"} class="flex-1 min-w-0 flex items-center gap-3">
                <span class={["badge", kind_color(m.kind), "badge-sm"]}>
                  {kind_label(m.kind)}
                </span>
                <div class="flex-1 min-w-0">
                  <p class="font-medium truncate">{m.name}</p>
                  <p class="text-xs text-neutral-content/60">
                    {format_relative(m.inserted_at, @current_user.timezone)} ·
                    intensity {m.intensity}/5
                    <%= if cat = Map.get(@categories_by_id, m.category_id) do %>
                      · {ElectricbrainWeb.CategoryPicker.breadcrumb(cat.path)}
                    <% end %>
                  </p>
                </div>
              </.link>
              <button
                phx-click="delete"
                phx-value-id={m.id}
                data-confirm="Delete this moment?"
                class="btn btn-xs btn-ghost text-error"
                title="Delete"
              >
                <.icon name="hero-x-mark-micro" class="size-4" />
              </button>
            </li>
          <% end %>
        </ul>
      <% end %>
    </Layouts.app>
    """
  end
end
