defmodule ElectricbrainWeb.HabitLive.Edit do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Habits.Availability
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Habits.RitualStep
  alias Electricbrain.Habits.Streak
  alias Electricbrain.Metrics.HabitMetric
  alias Electricbrain.Metrics.Metric
  alias ElectricbrainWeb.CategoryPicker

  import ElectricbrainWeb.HabitLive.FormFields

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    habit = load_habit(id, user)

    {:ok,
     socket
     |> assign(:page_title, "Edit · #{habit.title}")
     |> assign(:habit, habit)
     |> CategoryPicker.assign(user)
     |> CategoryPicker.attach()
     |> assign(:picker_selected_id, habit.category_id)
     |> assign(:edit_form, edit_form(habit, user))
     |> assign(:availability_form, availability_form(user))
     |> assign(:step_form, step_form(user))
     |> assign(:available_metrics, list_metrics(user))}
  end

  defp load_habit(id, user) do
    Habit
    |> Ash.get!(id,
      actor: user,
      load: [:availabilities, :ritual_steps, :completions, :metrics]
    )
  end

  defp list_metrics(user) do
    Metric
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(actor: user)
  end

  defp edit_form(habit, user) do
    habit
    |> AshPhoenix.Form.for_update(:update, actor: user)
    |> to_form()
  end

  defp availability_form(user) do
    Availability
    |> AshPhoenix.Form.for_create(:create, actor: user)
    |> to_form()
  end

  defp step_form(user) do
    RitualStep
    |> AshPhoenix.Form.for_create(:create, actor: user)
    |> to_form()
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.edit_form, params)
    {:noreply, assign(socket, edit_form: to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    user = socket.assigns.current_user
    params = Map.put(params, "category_id", socket.assigns.picker_selected_id)

    case AshPhoenix.Form.submit(socket.assigns.edit_form, params: params) do
      {:ok, habit} ->
        habit = load_habit(habit.id, user)

        {:noreply,
         socket
         |> assign(:habit, habit)
         |> assign(:edit_form, edit_form(habit, user))
         |> put_flash(:info, "Saved")}

      {:error, form} ->
        {:noreply, assign(socket, edit_form: to_form(form))}
    end
  end

  def handle_event("add_availability", %{"form" => params}, socket) do
    user = socket.assigns.current_user
    params = Map.put(params, "habit_id", socket.assigns.habit.id)

    case AshPhoenix.Form.submit(socket.assigns.availability_form, params: params) do
      {:ok, _availability} ->
        habit = load_habit(socket.assigns.habit.id, user)

        {:noreply,
         socket
         |> assign(:habit, habit)
         |> assign(:availability_form, availability_form(user))}

      {:error, form} ->
        {:noreply, assign(socket, availability_form: to_form(form))}
    end
  end

  def handle_event("delete_availability", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    Availability
    |> Ash.get!(id, actor: user)
    |> Ash.destroy!(actor: user)

    habit = load_habit(socket.assigns.habit.id, user)
    {:noreply, assign(socket, habit: habit)}
  end

  def handle_event("add_step", %{"form" => params}, socket) do
    user = socket.assigns.current_user
    params = Map.put(params, "habit_id", socket.assigns.habit.id)

    case AshPhoenix.Form.submit(socket.assigns.step_form, params: params) do
      {:ok, _step} ->
        habit = load_habit(socket.assigns.habit.id, user)

        {:noreply,
         socket
         |> assign(:habit, habit)
         |> assign(:step_form, step_form(user))}

      {:error, form} ->
        {:noreply, assign(socket, step_form: to_form(form))}
    end
  end

  def handle_event("delete_step", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    RitualStep
    |> Ash.get!(id, actor: user)
    |> Ash.destroy!(actor: user)

    habit = load_habit(socket.assigns.habit.id, user)
    {:noreply, assign(socket, habit: habit)}
  end

  def handle_event("attach_metric", %{"metric_id" => ""}, socket), do: {:noreply, socket}

  def handle_event("attach_metric", %{"metric_id" => metric_id}, socket) do
    user = socket.assigns.current_user
    habit_id = socket.assigns.habit.id

    HabitMetric
    |> Ash.Changeset.for_create(
      :create,
      %{habit_id: habit_id, metric_id: metric_id},
      actor: user
    )
    |> Ash.create!()

    {:noreply, assign(socket, :habit, load_habit(habit_id, user))}
  end

  def handle_event("detach_metric", %{"metric_id" => metric_id}, socket) do
    user = socket.assigns.current_user
    habit_id = socket.assigns.habit.id

    HabitMetric
    |> Ash.Query.filter(habit_id == ^habit_id and metric_id == ^metric_id)
    |> Ash.read!(actor: user)
    |> Enum.each(&Ash.destroy!(&1, actor: user))

    {:noreply, assign(socket, :habit, load_habit(habit_id, user))}
  end

  defp day_name(nil), do: "Every day"
  defp day_name(1), do: "Mon"
  defp day_name(2), do: "Tue"
  defp day_name(3), do: "Wed"
  defp day_name(4), do: "Thu"
  defp day_name(5), do: "Fri"
  defp day_name(6), do: "Sat"
  defp day_name(7), do: "Sun"

  defp format_time(time), do: Calendar.strftime(time, "%H:%M")

  defp format_hhmm(minutes) when is_integer(minutes) and minutes >= 0 do
    h = div(minutes, 60)
    m = rem(minutes, 60)
    :io_lib.format("~2..0B:~2..0B", [h, m]) |> IO.iodata_to_binary()
  end

  defp weekly_total_minutes(%{
         min_count: min_count,
         period: period,
         duration_minutes: duration
       })
       when is_integer(min_count) and is_integer(duration) and not is_nil(period) do
    per_period = min_count * duration

    case period do
      :day -> per_period * 7
      :week -> per_period
      :month -> div(per_period * 12, 52)
    end
  end

  defp weekly_total_minutes(_), do: nil

  # Heatmap cell colors. Hit → success, partial → warning, miss → error,
  # in-progress → base-300 (faint), future → near-invisible.
  defp streak_cell_class(:hit), do: "bg-success"
  defp streak_cell_class(:partial), do: "bg-warning"
  defp streak_cell_class(:miss), do: "bg-error/60"
  defp streak_cell_class(:in_progress), do: "bg-base-300"
  defp streak_cell_class(:future), do: "bg-base-300/30"
  defp streak_cell_class(_), do: "bg-base-300/30"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div>
        <.link navigate={~p"/habits"} class="btn btn-sm btn-ghost">
          <.icon name="hero-arrow-left-micro" class="size-4" /> Back to habits
        </.link>
      </div>

      <div>
        <h1 class="font-display text-3xl font-bold tracking-tight text-success">
          {@habit.title}
        </h1>
        <p class="text-sm text-neutral-content/70">
          Edit how this habit behaves and when it can be done.
        </p>
      </div>

      <.form
        for={@edit_form}
        id="edit-form"
        phx-change="validate"
        phx-submit="save"
        class="card bg-base-200 border border-base-300"
      >
        <div class="card-body space-y-3">
          <.habit_form_fields
            form={@edit_form}
            categories={@categories}
            categories_by_id={@categories_by_id}
            picker_selected_id={@picker_selected_id}
            picker_query={@picker_query}
            picker_open={@picker_open}
          />
          <div class="flex justify-end">
            <button type="submit" class="btn btn-primary">
              <.icon name="hero-check-micro" class="size-4" /> Save
            </button>
          </div>
        </div>
      </.form>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body">
          <div class="flex items-baseline justify-between gap-3 flex-wrap">
            <h2 class="card-title text-lg">Recent activity</h2>
            <%= if Streak.at_risk?(@habit, timezone: @current_user.timezone || "Etc/UTC") do %>
              <span class="badge badge-warning gap-1">
                <.icon name="hero-exclamation-triangle-micro" class="size-3" /> Don't miss twice
              </span>
            <% end %>
          </div>
          <p class="text-sm text-neutral-content/60">
            Last 8 weeks. Hover a square to see the count.
          </p>

          <div class="flex flex-wrap gap-0.5 mt-2">
            <%= for cell <- Streak.for_habit(@habit, timezone: @current_user.timezone || "Etc/UTC") do %>
              <div
                class={["size-3 rounded-sm", streak_cell_class(cell.status)]}
                title={"#{cell.date} — #{cell.count} #{if cell.count == 1, do: "completion", else: "completions"} (#{cell.status})"}
              >
              </div>
            <% end %>
          </div>

          <div class="flex items-center gap-3 text-xs text-neutral-content/60 mt-2">
            <span class="flex items-center gap-1">
              <span class={["size-2.5 rounded-sm", streak_cell_class(:hit)]}></span> Hit
            </span>
            <span class="flex items-center gap-1">
              <span class={["size-2.5 rounded-sm", streak_cell_class(:partial)]}></span> Partial
            </span>
            <span class="flex items-center gap-1">
              <span class={["size-2.5 rounded-sm", streak_cell_class(:miss)]}></span> Miss
            </span>
            <span class="flex items-center gap-1">
              <span class={["size-2.5 rounded-sm", streak_cell_class(:in_progress)]}></span>
              In progress
            </span>
          </div>
        </div>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body">
          <div class="flex items-baseline justify-between gap-3 flex-wrap">
            <h2 class="card-title text-lg">Availability windows</h2>
            <%= if total = weekly_total_minutes(@habit) do %>
              <span class="text-sm">
                <span class="text-neutral-content/60">Total per week:</span>
                <span class="font-mono font-medium text-accent ml-1">{format_hhmm(total)}</span>
              </span>
            <% end %>
          </div>
          <p class="text-sm text-neutral-content/60">
            When this habit may be scheduled. Empty means anytime.
          </p>

          <ul class="space-y-1 mt-2">
            <%= for a <- @habit.availabilities do %>
              <li class="flex items-center gap-3 py-1.5 px-2 rounded hover:bg-base-300/40">
                <span class="font-medium w-20">{day_name(a.day_of_week)}</span>
                <span class="text-sm text-neutral-content/80">
                  {format_time(a.start_time)} – {format_time(a.end_time)}
                </span>
                <span class="badge badge-ghost badge-sm font-mono">
                  {format_hhmm(Availability.duration_minutes(a))}
                </span>
                <div class="flex-1"></div>
                <button
                  type="button"
                  phx-click="delete_availability"
                  phx-value-id={a.id}
                  class="btn btn-xs btn-ghost text-error"
                >
                  <.icon name="hero-x-mark-micro" class="size-3.5" />
                </button>
              </li>
            <% end %>
            <%= if @habit.availabilities == [] do %>
              <li class="text-sm text-neutral-content/60 py-2">No windows set — anytime.</li>
            <% end %>
          </ul>

          <.form
            for={@availability_form}
            id="availability-form"
            phx-submit="add_availability"
            class="grid sm:grid-cols-[auto_auto_auto_1fr_auto] gap-3 items-end mt-4 pt-4 border-t border-base-300"
          >
            <div>
              <label class="label">
                <span class="label-text text-xs">Day</span>
              </label>
              <select
                name={@availability_form[:day_of_week].name}
                class="select select-bordered bg-base-100"
              >
                <option value="">Every day</option>
                <%= for d <- 1..7 do %>
                  <option value={d}>{day_name(d)}</option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="label">
                <span class="label-text text-xs">Start</span>
              </label>
              <input
                type="time"
                name={@availability_form[:start_time].name}
                class="input input-bordered bg-base-100"
                required
              />
            </div>
            <div>
              <label class="label">
                <span class="label-text text-xs">End</span>
              </label>
              <input
                type="time"
                name={@availability_form[:end_time].name}
                class="input input-bordered bg-base-100"
                required
              />
            </div>
            <div></div>
            <button type="submit" class="btn btn-primary">
              <.icon name="hero-plus-micro" class="size-4" /> Add window
            </button>
          </.form>
        </div>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body">
          <h2 class="card-title text-lg">Ritual</h2>
          <p class="text-sm text-neutral-content/60">
            Optional checklist for each instance. Habit isn't done until every step is ticked. Tick state persists across sessions.
          </p>

          <ul class="space-y-1 mt-2">
            <%= for step <- @habit.ritual_steps do %>
              <li class="flex items-center gap-3 py-1.5 px-2 rounded hover:bg-base-300/40">
                <.icon name="hero-list-bullet-micro" class="size-4 text-neutral-content/50" />
                <span class="text-sm">{step.title}</span>
                <div class="flex-1"></div>
                <button
                  type="button"
                  phx-click="delete_step"
                  phx-value-id={step.id}
                  class="btn btn-xs btn-ghost text-error"
                >
                  <.icon name="hero-x-mark-micro" class="size-3.5" />
                </button>
              </li>
            <% end %>
            <%= if @habit.ritual_steps == [] do %>
              <li class="text-sm text-neutral-content/60 py-2">
                No steps — habit completes in one tap.
              </li>
            <% end %>
          </ul>

          <.form
            for={@step_form}
            id="step-form"
            phx-submit="add_step"
            class="flex gap-3 items-end mt-4 pt-4 border-t border-base-300"
          >
            <div class="flex-1">
              <label class="label">
                <span class="label-text text-xs">Step</span>
              </label>
              <input
                type="text"
                name={@step_form[:title].name}
                class="input input-bordered bg-base-100 w-full"
                placeholder="e.g. brush teeth"
                required
              />
            </div>
            <button type="submit" class="btn btn-primary">
              <.icon name="hero-plus-micro" class="size-4" /> Add step
            </button>
          </.form>
        </div>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body">
          <h2 class="card-title text-lg">Metrics captured on completion</h2>
          <p class="text-sm text-neutral-content/60">
            When this habit is marked done, you'll be prompted to enter a value
            for each attached metric. Backfill or correct on the metric page.
          </p>

          <ul class="space-y-1 mt-2">
            <%= for metric <- @habit.metrics do %>
              <li class="flex items-center gap-3 py-1.5 px-2 rounded hover:bg-base-300/40">
                <.link navigate={~p"/metrics/#{metric.id}"} class="font-medium hover:underline">
                  {metric.name}
                </.link>
                <span class="text-xs text-neutral-content/60">{metric.unit}</span>
                <div class="flex-1"></div>
                <button
                  type="button"
                  phx-click="detach_metric"
                  phx-value-metric_id={metric.id}
                  class="btn btn-xs btn-ghost text-error"
                  title="Detach"
                >
                  <.icon name="hero-x-mark-micro" class="size-3.5" />
                </button>
              </li>
            <% end %>
            <%= if @habit.metrics == [] do %>
              <li class="text-sm text-neutral-content/60 py-2">
                No metrics attached. Pick one below to start capturing values.
              </li>
            <% end %>
          </ul>

          <% attached_ids = MapSet.new(@habit.metrics, & &1.id)
          attachable = Enum.reject(@available_metrics, &MapSet.member?(attached_ids, &1.id)) %>
          <%= if attachable != [] do %>
            <form
              phx-change="attach_metric"
              class="flex gap-3 items-end mt-4 pt-4 border-t border-base-300"
            >
              <div class="flex-1">
                <label class="label">
                  <span class="label-text text-xs">Attach metric</span>
                </label>
                <select name="metric_id" class="select select-bordered bg-base-100 w-full">
                  <option value="">Pick a metric…</option>
                  <%= for m <- attachable do %>
                    <option value={m.id}>{m.name} ({m.unit})</option>
                  <% end %>
                </select>
              </div>
            </form>
          <% else %>
            <p class="text-xs text-neutral-content/60 mt-2">
              No more metrics to attach. <.link navigate={~p"/metrics"} class="link link-primary">Create one</.link>.
            </p>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
