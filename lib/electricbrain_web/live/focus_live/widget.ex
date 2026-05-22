defmodule ElectricbrainWeb.FocusLive.Widget do
  @moduledoc """
  Floating-pill focus session widget. Mounted as a `live_component` from
  `Layouts.app` so it shows on every authenticated page. The current
  active session is fed in via `@focus_session` (kept fresh by the
  `attach_focus_session` hook in `LiveUserAuth`).

  Three states:

    * idle (no active session) — small "Start focus" pill, click opens
      the start dialog
    * running — countdown card, "Take break early" / "End" / "Abandon"
    * on_break — same card with break styling, "End" / "Abandon"
  """

  use ElectricbrainWeb, :live_component

  require Ash.Query

  alias Electricbrain.Categories.Category
  alias Electricbrain.Focus.Session
  alias Electricbrain.Habits.Habit
  alias Electricbrain.TimeBlocks.TimeBlock
  alias Electricbrain.Todos.Todo

  @target_tabs [:none, :todo, :habit, :time_block, :category]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:dialog_open, false)
     |> assign(:selected_tab, :none)
     |> assign(:selected_target_id, nil)
     |> assign(:work_minutes, 25)
     |> assign(:break_minutes, 5)
     |> assign(:options_by_tab, %{})}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      case socket.assigns[:current_user] do
        nil ->
          socket

        user ->
          socket
          |> assign_new(:work_minutes, fn -> user.focus_work_minutes end)
          |> assign_new(:break_minutes, fn -> user.focus_break_minutes end)
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("open_dialog", _, socket) do
    user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(:dialog_open, true)
     |> assign(:work_minutes, user.focus_work_minutes)
     |> assign(:break_minutes, user.focus_break_minutes)}
  end

  def handle_event("close_dialog", _, socket) do
    {:noreply, assign(socket, :dialog_open, false)}
  end

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)

    if tab in @target_tabs do
      socket =
        socket
        |> assign(:selected_tab, tab)
        |> assign(:selected_target_id, nil)
        |> load_options_for(tab)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_target", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_target_id, id)}
  end

  def handle_event("change", %{"work_minutes" => w, "break_minutes" => b}, socket) do
    {:noreply,
     socket
     |> assign(:work_minutes, parse_int(w, socket.assigns.work_minutes))
     |> assign(:break_minutes, parse_int(b, socket.assigns.break_minutes))}
  end

  def handle_event("start", _, socket) do
    user = socket.assigns.current_user

    attrs =
      %{
        duration_minutes: socket.assigns.work_minutes,
        break_minutes: socket.assigns.break_minutes
      }
      |> put_target(socket.assigns.selected_tab, socket.assigns.selected_target_id)

    case Session
         |> Ash.Changeset.for_create(:start, attrs, actor: user)
         |> Ash.create() do
      {:ok, _session} ->
        {:noreply,
         socket
         |> assign(:dialog_open, false)
         |> assign(:selected_target_id, nil)
         |> assign(:selected_tab, :none)}

      {:error, _} ->
        # The Track broadcast hasn't fired in the error path; just keep
        # the dialog open so the user can try again.
        {:noreply, socket}
    end
  end

  def handle_event("complete", _, socket) do
    transition(socket, :complete)
    {:noreply, socket}
  end

  def handle_event("abandon", _, socket) do
    transition(socket, :abandon)
    {:noreply, socket}
  end

  def handle_event("start_break", _, socket) do
    transition(socket, :start_break)
    {:noreply, socket}
  end

  defp transition(socket, action) do
    with %Session{} = session <- socket.assigns.focus_session do
      session
      |> Ash.Changeset.for_update(action, %{}, actor: socket.assigns.current_user)
      |> Ash.update()
    end
  end

  defp put_target(attrs, :none, _), do: attrs
  defp put_target(attrs, _, nil), do: attrs
  defp put_target(attrs, :todo, id), do: Map.put(attrs, :todo_id, id)
  defp put_target(attrs, :habit, id), do: Map.put(attrs, :habit_id, id)
  defp put_target(attrs, :time_block, id), do: Map.put(attrs, :time_block_id, id)
  defp put_target(attrs, :category, id), do: Map.put(attrs, :category_id, id)

  defp parse_int(s, fallback) do
    case Integer.parse(to_string(s)) do
      {n, _} -> n
      _ -> fallback
    end
  end

  defp load_options_for(socket, :none), do: socket

  defp load_options_for(socket, tab) do
    if Map.has_key?(socket.assigns.options_by_tab, tab) do
      socket
    else
      user = socket.assigns.current_user

      assign(
        socket,
        :options_by_tab,
        Map.put(socket.assigns.options_by_tab, tab, list(tab, user))
      )
    end
  end

  defp list(:todo, user) do
    Todo
    |> Ash.Query.filter(status in [:pending, :in_progress])
    |> Ash.Query.sort(title: :asc)
    |> Ash.read!(actor: user)
    |> Enum.map(&%{id: &1.id, label: &1.title})
  end

  defp list(:habit, user) do
    Habit
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(actor: user)
    |> Enum.map(&%{id: &1.id, label: &1.name})
  end

  defp list(:time_block, user) do
    TimeBlock
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(actor: user)
    |> Enum.map(&%{id: &1.id, label: &1.name})
  end

  defp list(:category, user) do
    Category
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(actor: user)
    |> Enum.map(&%{id: &1.id, label: &1.name})
  end

  defp target_label(nil), do: nil
  defp target_label(%Session{todo: %{title: t}}), do: t
  defp target_label(%Session{habit: %{name: n}}), do: n
  defp target_label(%Session{time_block: %{name: n}}), do: n
  defp target_label(%Session{category: %{name: n}}), do: n
  defp target_label(_), do: nil

  defp ends_at(%Session{status: :running, started_at: at, duration_minutes: m}),
    do: DateTime.add(at, m * 60, :second)

  defp ends_at(%Session{status: :on_break, break_started_at: at, break_minutes: m}),
    do: DateTime.add(at, m * 60, :second)

  defp ends_at(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="fixed bottom-5 left-5 z-30">
      <%= cond do %>
        <% @focus_session && @focus_session.status == :running -> %>
          <.running_card session={@focus_session} myself={@myself} />
        <% @focus_session && @focus_session.status == :on_break -> %>
          <.break_card session={@focus_session} myself={@myself} />
        <% @dialog_open -> %>
          <.start_dialog
            myself={@myself}
            selected_tab={@selected_tab}
            selected_target_id={@selected_target_id}
            work_minutes={@work_minutes}
            break_minutes={@break_minutes}
            options_by_tab={@options_by_tab}
          />
        <% true -> %>
          <button
            type="button"
            phx-click="open_dialog"
            phx-target={@myself}
            class="btn btn-sm btn-primary shadow-lg gap-2"
            title="Start a focus session"
          >
            <.icon name="hero-clock-micro" class="size-4" /> Focus
          </button>
      <% end %>
    </div>
    """
  end

  attr :session, :map, required: true
  attr :myself, :any, required: true

  defp running_card(assigns) do
    assigns =
      assigns
      |> assign(:ends_at_iso, DateTime.to_iso8601(ends_at(assigns.session)))
      |> assign(:label, target_label(assigns.session) || "Focus session")

    ~H"""
    <div class="card bg-base-200 border border-primary/40 shadow-lg min-w-56">
      <div class="card-body p-3">
        <div class="flex items-center justify-between gap-2">
          <div class="flex items-center gap-2">
            <span class="size-2 rounded-full bg-primary animate-pulse"></span>
            <span class="text-xs uppercase tracking-wide text-primary">Focusing</span>
          </div>
          <div
            id={"focus-countdown-#{@session.id}"}
            phx-hook="FocusCountdown"
            data-ends-at={@ends_at_iso}
            class="font-mono text-lg font-semibold"
          >
            --:--
          </div>
        </div>
        <p class="text-sm font-medium truncate" title={@label}>{@label}</p>
        <div class="flex gap-1 justify-end">
          <button
            type="button"
            phx-click="start_break"
            phx-target={@myself}
            class="btn btn-xs btn-ghost"
          >
            Take break
          </button>
          <button
            type="button"
            phx-click="complete"
            phx-target={@myself}
            class="btn btn-xs btn-ghost"
          >
            End
          </button>
          <button
            type="button"
            phx-click="abandon"
            phx-target={@myself}
            class="btn btn-xs btn-ghost text-error"
            data-confirm="Abandon this session?"
          >
            <.icon name="hero-x-mark-micro" class="size-4" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :session, :map, required: true
  attr :myself, :any, required: true

  defp break_card(assigns) do
    assigns =
      assigns
      |> assign(:ends_at_iso, DateTime.to_iso8601(ends_at(assigns.session)))
      |> assign(:label, target_label(assigns.session) || "Focus session")

    ~H"""
    <div class="card bg-base-200 border border-accent/40 shadow-lg min-w-56">
      <div class="card-body p-3">
        <div class="flex items-center justify-between gap-2">
          <div class="flex items-center gap-2">
            <span class="size-2 rounded-full bg-accent"></span>
            <span class="text-xs uppercase tracking-wide text-accent">On break</span>
          </div>
          <div
            id={"focus-countdown-#{@session.id}"}
            phx-hook="FocusCountdown"
            data-ends-at={@ends_at_iso}
            class="font-mono text-lg font-semibold"
          >
            --:--
          </div>
        </div>
        <p class="text-sm text-neutral-content/70 truncate" title={@label}>
          {@label}
        </p>
        <div class="flex gap-1 justify-end">
          <button
            type="button"
            phx-click="complete"
            phx-target={@myself}
            class="btn btn-xs btn-ghost"
          >
            End break
          </button>
          <button
            type="button"
            phx-click="abandon"
            phx-target={@myself}
            class="btn btn-xs btn-ghost text-error"
            data-confirm="Abandon this session?"
          >
            <.icon name="hero-x-mark-micro" class="size-4" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :myself, :any, required: true
  attr :selected_tab, :atom, required: true
  attr :selected_target_id, :any, required: true
  attr :work_minutes, :integer, required: true
  attr :break_minutes, :integer, required: true
  attr :options_by_tab, :map, required: true

  defp start_dialog(assigns) do
    assigns = assign(assigns, :options, Map.get(assigns.options_by_tab, assigns.selected_tab, []))

    ~H"""
    <div class="card bg-base-200 border border-base-300 shadow-lg w-80">
      <div class="card-body p-3 space-y-3">
        <div class="flex items-center justify-between">
          <h3 class="font-semibold">Start focus</h3>
          <button
            type="button"
            phx-click="close_dialog"
            phx-target={@myself}
            class="btn btn-xs btn-ghost"
            aria-label="Close"
          >
            <.icon name="hero-x-mark-micro" class="size-4" />
          </button>
        </div>

        <div>
          <p class="text-xs uppercase tracking-wide text-neutral-content/60 mb-1">Focus on</p>
          <div class="flex flex-wrap gap-1">
            <%= for tab <- [:none, :todo, :habit, :time_block, :category] do %>
              <button
                type="button"
                phx-click="select_tab"
                phx-value-tab={tab}
                phx-target={@myself}
                class={[
                  "btn btn-xs",
                  if(@selected_tab == tab, do: "btn-primary", else: "btn-ghost")
                ]}
              >
                {tab_label(tab)}
              </button>
            <% end %>
          </div>
        </div>

        <%= if @selected_tab != :none do %>
          <div class="max-h-40 overflow-y-auto border border-base-300 rounded-box">
            <%= if @options == [] do %>
              <p class="p-3 text-xs text-neutral-content/60 italic">No matches.</p>
            <% else %>
              <%= for opt <- @options do %>
                <button
                  type="button"
                  phx-click="select_target"
                  phx-value-id={opt.id}
                  phx-target={@myself}
                  class={[
                    "w-full text-left px-3 py-1.5 text-sm hover:bg-base-300/60",
                    if(@selected_target_id == opt.id, do: "bg-primary/20 font-medium", else: "")
                  ]}
                >
                  {opt.label}
                </button>
              <% end %>
            <% end %>
          </div>
        <% end %>

        <form phx-change="change" phx-target={@myself} class="grid grid-cols-2 gap-2">
          <label class="text-xs">
            <span class="text-neutral-content/60">Work (min)</span>
            <input
              type="number"
              name="work_minutes"
              value={@work_minutes}
              min="1"
              max="240"
              class="input input-sm input-bordered w-full bg-base-100"
            />
          </label>
          <label class="text-xs">
            <span class="text-neutral-content/60">Break (min)</span>
            <input
              type="number"
              name="break_minutes"
              value={@break_minutes}
              min="0"
              max="60"
              class="input input-sm input-bordered w-full bg-base-100"
            />
          </label>
        </form>

        <button
          type="button"
          phx-click="start"
          phx-target={@myself}
          class="btn btn-sm btn-primary w-full"
        >
          <.icon name="hero-play-micro" class="size-4" /> Start
        </button>
      </div>
    </div>
    """
  end

  defp tab_label(:none), do: "Nothing"
  defp tab_label(:todo), do: "Todo"
  defp tab_label(:habit), do: "Habit"
  defp tab_label(:time_block), do: "Time block"
  defp tab_label(:category), do: "Category"
end
