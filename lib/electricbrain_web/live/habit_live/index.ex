defmodule ElectricbrainWeb.HabitLive.Index do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Habits.Completion
  alias Electricbrain.Habits.Habit
  alias ElectricbrainWeb.CategoryPicker

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Habits")
     |> CategoryPicker.assign(user)
     |> CategoryPicker.attach()
     |> assign(:form, new_form(user))
     |> assign(:habits, list_habits(user))}
  end

  defp new_form(user) do
    Habit
    |> AshPhoenix.Form.for_create(:create, actor: user)
    |> to_form()
  end

  defp list_habits(user) do
    Habit
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load(:completions)
    |> Ash.read!(actor: user)
    |> Enum.map(fn habit ->
      Map.put(
        habit,
        :period_count,
        count_in_period(habit.completions, habit.period, user.timezone)
      )
    end)
  end

  defp count_in_period(completions, period, timezone) do
    start = Electricbrain.Timezones.period_start(period, timezone)

    Enum.count(completions, fn completion ->
      DateTime.compare(completion.completed_at, start) != :lt
    end)
  end

  defp period_label(:day), do: "today"
  defp period_label(:week), do: "this week"
  defp period_label(:month), do: "this month"

  defp progress_class(habit) do
    cond do
      habit.period_count >= habit.min_count -> "badge badge-success badge-sm"
      habit.period_count == 0 -> "badge badge-error badge-sm"
      true -> "badge badge-warning badge-sm"
    end
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    user = socket.assigns.current_user
    params = Map.put(params, "category_id", socket.assigns.picker_selected_id)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _habit} ->
        {:noreply,
         socket
         |> assign(:form, new_form(user))
         |> CategoryPicker.reset()
         |> assign(:habits, list_habits(user))
         |> put_flash(:info, "Habit added")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  def handle_event("mark_done", %{"id" => habit_id}, socket) do
    user = socket.assigns.current_user

    Completion
    |> Ash.Changeset.for_create(:create, %{habit_id: habit_id}, actor: user)
    |> Ash.create!()

    {:noreply, assign(socket, habits: list_habits(user))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    Habit
    |> Ash.get!(id, actor: user)
    |> Ash.destroy!(actor: user)

    {:noreply, assign(socket, habits: list_habits(user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div>
        <h1 class="font-display text-3xl font-bold tracking-tight text-success drop-shadow-[0_0_12px_var(--color-success)]">
          Habits
        </h1>
        <p class="text-sm text-neutral-content/70">
          Rhythms that keep the brain firing — track the commitment, not the minute.
        </p>
      </div>

      <.form
        for={@form}
        id="habit-form"
        phx-change="validate"
        phx-submit="save"
        class="card bg-base-200 border border-base-300"
      >
        <div class="card-body grid sm:grid-cols-[1fr_minmax(12rem,18rem)_auto_auto_auto] gap-3 items-end">
          <div>
            <label class="label">
              <span class="label-text text-xs">Title</span>
            </label>
            <input
              type="text"
              name={@form[:title].name}
              value={Phoenix.HTML.Form.normalize_value("text", @form[:title].value)}
              class="input input-bordered w-full bg-base-100"
              placeholder="Exercise, meditate, read…"
              autocomplete="off"
              required
            />
          </div>

          <div>
            <label class="label">
              <span class="label-text text-xs">Category</span>
            </label>
            <CategoryPicker.picker
              categories={@categories}
              categories_by_id={@categories_by_id}
              selected_id={@picker_selected_id}
              query={@picker_query}
              open={@picker_open}
            />
          </div>

          <div>
            <label class="label">
              <span class="label-text text-xs">Min count</span>
            </label>
            <input
              type="number"
              name={@form[:min_count].name}
              value={Phoenix.HTML.Form.normalize_value("number", @form[:min_count].value) || 1}
              min="1"
              class="input input-bordered w-20 bg-base-100"
            />
          </div>

          <div>
            <label class="label">
              <span class="label-text text-xs">Period</span>
            </label>
            <select
              name={@form[:period].name}
              class="select select-bordered bg-base-100"
            >
              <option value="day">per day</option>
              <option value="week" selected>per week</option>
              <option value="month">per month</option>
            </select>
          </div>

          <button type="submit" class="btn btn-primary">
            <.icon name="hero-plus-micro" class="size-4" /> Add
          </button>
        </div>
      </.form>

      <ul class="space-y-2">
        <%= for habit <- @habits do %>
          <li class="flex items-center gap-3 p-3 bg-base-200 border border-base-300 rounded-box">
            <button
              type="button"
              phx-click="mark_done"
              phx-value-id={habit.id}
              class="btn btn-circle btn-sm btn-success"
              title="Mark done"
            >
              <.icon name="hero-check-micro" class="size-4" />
            </button>
            <div class="flex-1 min-w-0">
              <p class="font-medium truncate">{habit.title}</p>
              <div class="flex flex-wrap items-center gap-2 text-xs text-neutral-content/60 mt-0.5">
                <%= if cat = Map.get(@categories_by_id, habit.category_id) do %>
                  <span class="badge badge-outline badge-sm">
                    {CategoryPicker.breadcrumb(cat.path)}
                  </span>
                <% end %>
                <span class={progress_class(habit)}>
                  {habit.period_count} / {habit.min_count} {period_label(habit.period)}
                </span>
              </div>
            </div>
            <.link
              navigate={~p"/habits/#{habit.id}/schedule"}
              class="btn btn-xs btn-ghost"
              title="Schedule"
            >
              <.icon name="hero-calendar-micro" class="size-4" />
            </.link>
            <button
              phx-click="delete"
              phx-value-id={habit.id}
              data-confirm={"Delete \"#{habit.title}\" and all its completions?"}
              class="btn btn-xs btn-ghost text-error"
            >
              <.icon name="hero-x-mark-micro" class="size-4" />
            </button>
          </li>
        <% end %>
        <%= if @habits == [] do %>
          <li class="text-center py-12 text-neutral-content/60">
            No habits yet. Add one above.
          </li>
        <% end %>
      </ul>
    </Layouts.app>
    """
  end
end
