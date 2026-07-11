defmodule ElectricbrainWeb.TrainingLive.Index do
  @moduledoc """
  The training home: this week's strip (training days vs trained
  days), the next prescribed session, and recent history. First visit
  seeds the default pool + A/B templates (`Training.ensure_setup!/1`).
  """

  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Training
  alias Electricbrain.Training.Workout

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    :ok = Training.ensure_setup!(user)

    {:ok,
     socket
     |> assign(:page_title, "Training")
     |> load()}
  end

  defp load(socket) do
    user = socket.assigns.current_user

    socket
    |> assign(:settings, Training.settings_for(user))
    |> assign(:active, Training.active_workout(user))
    |> assign(:next, Training.next_session(user))
    |> assign(:exercises, Training.exercises_for(user))
    |> assign(:recent, recent_workouts(user))
    |> assign(:completed_count, Training.completed_count(user))
  end

  defp recent_workouts(user) do
    Workout
    |> Ash.Query.filter(status == :completed)
    |> Ash.Query.sort(ended_at: :desc)
    |> Ash.Query.limit(8)
    |> Ash.Query.load(:sets)
    |> Ash.read!(actor: user)
  end

  @impl true
  def handle_event("start", _params, socket) do
    user = socket.assigns.current_user

    case Training.start_workout!(user) do
      {:ok, _workout} ->
        {:noreply, push_navigate(socket, to: ~p"/training/session")}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Nothing to prescribe — check your templates and exercises")}
    end
  end

  # ---- view helpers ----------------------------------------------------

  defp week_days(user, settings, recent) do
    today = user.timezone |> DateTime.now!() |> DateTime.to_date()
    monday = Date.add(today, -(Date.day_of_week(today) - 1))

    trained_days =
      recent
      |> Enum.map(fn workout ->
        workout.ended_at |> DateTime.shift_zone!(user.timezone) |> DateTime.to_date()
      end)
      |> MapSet.new()

    Enum.map(0..6, fn offset ->
      date = Date.add(monday, offset)

      %{
        date: date,
        today?: date == today,
        training_day?: Date.day_of_week(date) in settings.training_days,
        trained?: MapSet.member?(trained_days, date)
      }
    end)
  end

  defp item_line(item) do
    weight =
      case item.weight_kg do
        nil -> ""
        weight -> " @ #{weight_str(weight)} kg"
      end

    "#{item.exercise_name} #{item.sets}×#{item.reps}#{weight}"
  end

  defp weight_str(decimal), do: decimal |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp workout_summary(workout) do
    workout.sets
    |> Enum.filter(&(&1.slot_kind == :fixed))
    |> Enum.map(& &1.exercise_name)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp local_day(datetime, tz),
    do: datetime |> DateTime.shift_zone!(tz) |> Calendar.strftime("%a %d %b")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-accent">
            Training
          </h1>
          <p class="text-sm text-neutral-content/70">
            Linear A/B — add weight when you win, deload when you stall.
          </p>
        </div>
        <.link
          navigate={~p"/training/settings"}
          class="btn btn-ghost btn-sm"
          title="Training settings"
        >
          <.icon name="hero-cog-6-tooth-micro" class="size-4" />
        </.link>
      </div>

      <div class="flex gap-2">
        <div
          :for={day <- week_days(@current_user, @settings, @recent)}
          class={[
            "flex-1 rounded-box border p-2 text-center",
            day.today? && "border-primary",
            !day.today? && "border-base-300",
            !day.training_day? && "opacity-40"
          ]}
        >
          <p class="text-xs text-neutral-content/60">{Calendar.strftime(day.date, "%a")}</p>
          <p class="text-sm font-medium">{day.date.day}</p>
          <p class="text-xs h-4">
            <%= cond do %>
              <% day.trained? -> %>
                <.icon name="hero-check-circle-micro" class="size-4 text-success inline" />
              <% day.training_day? -> %>
                <.icon name="hero-bolt-micro" class="size-4 text-neutral-content/40 inline" />
              <% true -> %>
            <% end %>
          </p>
        </div>
      </div>

      <%= if @active do %>
        <div class="card bg-base-200 border border-primary">
          <div class="card-body">
            <h2 class="card-title">Workout in progress — Session {@active.template_name}</h2>
            <p class="text-sm text-neutral-content/70">
              {Enum.count(@active.sets, & &1.completed_at)}/{length(@active.sets)} sets done
            </p>
            <div class="flex justify-end">
              <.link navigate={~p"/training/session"} class="btn btn-primary btn-sm">
                Resume workout
              </.link>
            </div>
          </div>
        </div>
      <% else %>
        <div class="card bg-base-200 border border-base-300">
          <div class="card-body">
            <%= case @next do %>
              <% %{template: template, items: items} -> %>
                <h2 class="card-title">Next — Session {template.name}</h2>
                <ul class="text-sm space-y-1">
                  <li :for={item <- items} class="flex items-center gap-2">
                    <span :if={item.slot_kind == :accessory} class="badge badge-ghost badge-xs">
                      accessory
                    </span>
                    {item_line(item)}
                  </li>
                </ul>
                <div class="flex justify-end">
                  <button phx-click="start" class="btn btn-primary btn-sm">
                    <.icon name="hero-play-micro" class="size-4" /> Start workout
                  </button>
                </div>
              <% {:error, _} -> %>
                <p class="text-sm text-neutral-content/60">
                  No templates to prescribe from — set them up in <.link
                    navigate={~p"/training/settings"}
                    class="underline"
                  >settings</.link>.
                </p>
            <% end %>
          </div>
        </div>

        <div :if={@completed_count == 0} class="card bg-warning/10 border border-warning/40">
          <div class="card-body p-4 text-sm">
            <p>
              <.icon name="hero-exclamation-triangle-micro" class="size-4 inline" />
              Starting weights are conservative defaults — set your actual working weights in
              <.link navigate={~p"/training/settings"} class="underline font-medium">
                training settings
              </.link>
              before your first session.
            </p>
          </div>
        </div>
      <% end %>

      <div :if={@recent != []} class="card bg-base-200 border border-base-300">
        <div class="card-body p-4">
          <h2 class="card-title text-base">Recent sessions</h2>
          <ul class="divide-y divide-base-300/60">
            <li :for={workout <- @recent} class="py-2 text-sm flex items-center gap-3">
              <span class="badge badge-ghost badge-sm">{workout.template_name}</span>
              <span class="flex-1 min-w-0 truncate">{workout_summary(workout)}</span>
              <span class="text-neutral-content/60">
                {local_day(workout.ended_at, @current_user.timezone)}
              </span>
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
