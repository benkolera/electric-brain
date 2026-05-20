defmodule ElectricbrainWeb.HabitLive.Index do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Habits.Completion
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Habits.StepCheck
  alias Electricbrain.Habits.Streak
  alias Electricbrain.Metrics.Measurement
  alias ElectricbrainWeb.CategoryPicker

  import ElectricbrainWeb.HabitLive.FormFields

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Habits")
     |> CategoryPicker.assign(user)
     |> CategoryPicker.attach()
     |> assign(:form, new_form(user))
     |> assign(:create_open, false)
     |> assign(:ritual_open_id, nil)
     |> assign(:capture_completion_id, nil)
     |> assign(:capture_habit_id, nil)
     |> assign(:habits, list_habits(user))}
  end

  @impl true
  def handle_params(%{"ritual" => habit_id}, _uri, socket) do
    user = socket.assigns.current_user
    habit = find_habit(socket.assigns.habits, habit_id)

    socket =
      if habit && habit.ritual_steps != [] do
        ensure_in_progress(habit, user)

        socket
        |> assign(:habits, list_habits(user))
        |> assign(:ritual_open_id, habit_id)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp new_form(user) do
    Habit
    |> AshPhoenix.Form.for_create(:create, actor: user)
    |> to_form()
  end

  defp list_habits(user) do
    Habit
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.load([:ritual_steps, :metrics, completions: [:step_checks]])
    |> Ash.read!(actor: user)
    |> Enum.map(&decorate_habit(&1, user))
  end

  defp decorate_habit(habit, user) do
    in_progress = Enum.find(habit.completions, &is_nil(&1.completed_at))
    finalized = Enum.reject(habit.completions, &is_nil(&1.completed_at))

    habit
    |> Map.put(:in_progress_completion, in_progress)
    |> Map.put(:period_count, count_in_period(finalized, habit.period, user.timezone))
  end

  defp count_in_period(_completions, nil, _timezone), do: 0

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

  defp ritual_progress(habit) do
    case habit.in_progress_completion do
      nil ->
        nil

      completion ->
        checked = MapSet.new(completion.step_checks, & &1.ritual_step_id)
        done = Enum.count(habit.ritual_steps, &MapSet.member?(checked, &1.id))
        {done, length(habit.ritual_steps)}
    end
  end

  defp step_checked?(completion, step_id) do
    Enum.any?(completion.step_checks, &(&1.ritual_step_id == step_id))
  end

  defp find_habit(habits, id), do: Enum.find(habits, &(&1.id == id))

  @impl true
  def handle_event("open_create", _params, socket) do
    {:noreply, assign(socket, :create_open, true)}
  end

  def handle_event("close_create", _params, socket) do
    user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(:create_open, false)
     |> assign(:form, new_form(user))
     |> CategoryPicker.reset()}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: to_form(form))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    user = socket.assigns.current_user
    params = Map.put(params, "category_id", socket.assigns.picker_selected_id)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _habit} ->
        {:noreply,
         socket
         |> assign(:form, new_form(user))
         |> assign(:create_open, false)
         |> CategoryPicker.reset()
         |> assign(:habits, list_habits(user))
         |> put_flash(:info, "Habit added")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  def handle_event("mark_done", %{"id" => habit_id}, socket) do
    user = socket.assigns.current_user
    habit = find_habit(socket.assigns.habits, habit_id)

    cond do
      habit == nil ->
        {:noreply, socket}

      habit.ritual_steps == [] ->
        completion =
          Completion
          |> Ash.Changeset.for_create(:create, %{habit_id: habit_id}, actor: user)
          |> Ash.create!()

        {:noreply,
         socket
         |> assign(:habits, list_habits(user))
         |> maybe_open_capture(habit, completion.id)}

      true ->
        ensure_in_progress(habit, user)

        {:noreply,
         socket
         |> assign(:habits, list_habits(user))
         |> assign(:ritual_open_id, habit.id)}
    end
  end

  def handle_event("close_ritual", _params, socket) do
    {:noreply, assign(socket, :ritual_open_id, nil)}
  end

  def handle_event("toggle_step", %{"step_id" => step_id}, socket) do
    user = socket.assigns.current_user
    habit = find_habit(socket.assigns.habits, socket.assigns.ritual_open_id)

    finalized_completion_id =
      if habit && habit.in_progress_completion do
        completion = habit.in_progress_completion

        case Enum.find(completion.step_checks, &(&1.ritual_step_id == step_id)) do
          nil ->
            StepCheck
            |> Ash.Changeset.for_create(
              :create,
              %{completion_id: completion.id, ritual_step_id: step_id},
              actor: user
            )
            |> Ash.create!()

          check ->
            check |> Ash.destroy!(actor: user)
        end

        maybe_finalize(habit.id, user)
      end

    habits = list_habits(user)
    refreshed = find_habit(habits, socket.assigns.ritual_open_id)
    open_id = if refreshed && refreshed.in_progress_completion, do: refreshed.id, else: nil

    socket =
      if finalized_completion_id && refreshed do
        maybe_open_capture(socket, refreshed, finalized_completion_id)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:habits, habits)
     |> assign(:ritual_open_id, open_id)}
  end

  def handle_event("dismiss_capture", _params, socket) do
    {:noreply,
     socket
     |> assign(:capture_completion_id, nil)
     |> assign(:capture_habit_id, nil)}
  end

  def handle_event("submit_capture", %{"values" => values}, socket) do
    user = socket.assigns.current_user
    completion_id = socket.assigns.capture_completion_id

    if completion_id do
      Enum.each(values, fn {metric_id, value_str} ->
        case parse_decimal(value_str) do
          nil ->
            :skip

          decimal ->
            Measurement
            |> Ash.Changeset.for_create(
              :create,
              %{
                metric_id: metric_id,
                completion_id: completion_id,
                value: decimal
              },
              actor: user
            )
            |> Ash.create!()
        end
      end)
    end

    {:noreply,
     socket
     |> assign(:capture_completion_id, nil)
     |> assign(:capture_habit_id, nil)
     |> assign(:habits, list_habits(user))
     |> put_flash(:info, "Captured")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    Habit
    |> Ash.get!(id, actor: user)
    |> Ash.destroy!(actor: user)

    {:noreply, assign(socket, habits: list_habits(user))}
  end

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(str) when is_binary(str) do
    case Decimal.parse(str) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp maybe_open_capture(socket, habit, completion_id) do
    if habit.metrics != [] do
      socket
      |> assign(:capture_completion_id, completion_id)
      |> assign(:capture_habit_id, habit.id)
    else
      socket
    end
  end

  defp ensure_in_progress(habit, user) do
    case habit.in_progress_completion do
      nil ->
        Completion
        |> Ash.Changeset.for_create(:start, %{habit_id: habit.id}, actor: user)
        |> Ash.create!()

      _ ->
        :ok
    end
  end

  defp maybe_finalize(habit_id, user) do
    habit =
      Habit
      |> Ash.Query.filter(id == ^habit_id)
      |> Ash.Query.load([:ritual_steps, completions: [:step_checks]])
      |> Ash.read_one!(actor: user)

    completion = Enum.find(habit.completions, &is_nil(&1.completed_at))

    if completion do
      step_ids = MapSet.new(habit.ritual_steps, & &1.id)
      checked = MapSet.new(completion.step_checks, & &1.ritual_step_id)

      if MapSet.size(step_ids) > 0 and MapSet.subset?(step_ids, checked) do
        completion
        |> Ash.Changeset.for_update(:finalize, %{}, actor: user)
        |> Ash.update!()

        completion.id
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div>
        <h1 class="font-display text-3xl font-bold tracking-tight text-success drop-shadow-[0_0_12px_var(--color-success)]">
          Habits
        </h1>
        <p class="text-sm text-neutral-content/70">
          Rhythms that keep the brain firing — track the commitment, not the minute.
        </p>
      </div>

      <div class="flex justify-end">
        <button type="button" phx-click="open_create" class="btn btn-primary">
          <.icon name="hero-plus-micro" class="size-4" /> Add habit
        </button>
      </div>

      <%= if @create_open do %>
        <div class="modal modal-open" phx-window-keydown="close_create" phx-key="escape">
          <div class="modal-box max-w-2xl bg-base-200 border border-base-300">
            <h2 class="font-bold text-lg mb-3">New habit</h2>
            <.form
              for={@form}
              id="habit-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-3"
            >
              <.habit_form_fields
                form={@form}
                categories={@categories}
                categories_by_id={@categories_by_id}
                picker_selected_id={@picker_selected_id}
                picker_query={@picker_query}
                picker_open={@picker_open}
              />

              <div class="modal-action">
                <button type="button" phx-click="close_create" class="btn btn-ghost">
                  Cancel
                </button>
                <button type="submit" class="btn btn-primary">
                  <.icon name="hero-plus-micro" class="size-4" /> Add habit
                </button>
              </div>
            </.form>
          </div>
          <div class="modal-backdrop" phx-click="close_create"></div>
        </div>
      <% end %>

      <%= if ritual_habit = @ritual_open_id && find_habit(@habits, @ritual_open_id) do %>
        <div class="modal modal-open" phx-window-keydown="close_ritual" phx-key="escape">
          <div class="modal-box max-w-lg bg-base-200 border border-base-300">
            <h2 class="font-bold text-lg mb-1">{ritual_habit.title}</h2>
            <p class="text-sm text-neutral-content/60 mb-4">
              Tick each step as you go. Closing the modal keeps your progress.
            </p>
            <ul class="space-y-2">
              <%= for step <- ritual_habit.ritual_steps do %>
                <% checked =
                  ritual_habit.in_progress_completion &&
                    step_checked?(ritual_habit.in_progress_completion, step.id) %>
                <li class="flex items-center gap-3">
                  <button
                    type="button"
                    phx-click="toggle_step"
                    phx-value-step_id={step.id}
                    class={[
                      "btn btn-sm flex-1 justify-start",
                      (checked && "btn-success") || "btn-outline"
                    ]}
                  >
                    <.icon
                      name={
                        if checked, do: "hero-check-circle-micro", else: "hero-circle-stack-micro"
                      }
                      class="size-4"
                    />
                    <span class={if checked, do: "line-through opacity-70", else: ""}>
                      {step.title}
                    </span>
                  </button>
                </li>
              <% end %>
            </ul>
            <div class="modal-action">
              <button type="button" phx-click="close_ritual" class="btn btn-ghost">Close</button>
            </div>
          </div>
          <div class="modal-backdrop" phx-click="close_ritual"></div>
        </div>
      <% end %>

      <% capture_habit = @capture_habit_id && find_habit(@habits, @capture_habit_id) %>
      <%= if capture_habit do %>
        <div class="modal modal-open" phx-window-keydown="dismiss_capture" phx-key="escape">
          <div class="modal-box max-w-md bg-base-200 border border-base-300">
            <h2 class="font-bold text-lg mb-1">{capture_habit.title}</h2>
            <p class="text-sm text-neutral-content/60 mb-4">
              Record a value for each attached metric. You can skip and backfill later.
            </p>
            <form phx-submit="submit_capture" class="space-y-3">
              <%= for metric <- capture_habit.metrics do %>
                <div>
                  <label class="label">
                    <span class="label-text">{metric.name}</span>
                    <span class="label-text-alt text-neutral-content/60">{metric.unit}</span>
                  </label>
                  <input
                    type="number"
                    step="any"
                    name={"values[#{metric.id}]"}
                    class="input input-bordered w-full bg-base-100"
                    autocomplete="off"
                    required
                  />
                </div>
              <% end %>
              <div class="modal-action">
                <button type="button" phx-click="dismiss_capture" class="btn btn-ghost">
                  Skip
                </button>
                <button type="submit" class="btn btn-primary">Save</button>
              </div>
            </form>
          </div>
          <div class="modal-backdrop" phx-click="dismiss_capture"></div>
        </div>
      <% end %>

      <ul class="space-y-2">
        <%= for habit <- @habits do %>
          <li class="flex items-center gap-3 p-3 bg-base-200 border border-base-300 rounded-box">
            <button
              type="button"
              phx-click="mark_done"
              phx-value-id={habit.id}
              class="btn btn-circle btn-sm btn-success"
              title={if habit.ritual_steps == [], do: "Mark done", else: "Open ritual"}
            >
              <.icon
                name={
                  if habit.ritual_steps == [], do: "hero-check-micro", else: "hero-list-bullet-micro"
                }
                class="size-4"
              />
            </button>
            <div class="flex-1 min-w-0">
              <p class="font-medium truncate">{habit.title}</p>
              <div class="flex flex-wrap items-center gap-2 text-xs text-neutral-content/60 mt-0.5">
                <%= if cat = Map.get(@categories_by_id, habit.category_id) do %>
                  <span class="badge badge-outline badge-sm">
                    {CategoryPicker.breadcrumb(cat.path)}
                  </span>
                <% end %>
                <%= if habit.min_count && habit.period do %>
                  <span class={progress_class(habit)}>
                    {habit.period_count} / {habit.min_count} {period_label(habit.period)}
                  </span>
                <% end %>
                <%= if progress = ritual_progress(habit) do %>
                  <% {done, total} = progress %>
                  <span class="badge badge-info badge-sm" title="Ritual in progress">
                    <.icon name="hero-list-bullet-micro" class="size-3" /> {done}/{total}
                  </span>
                <% end %>
                <%= if Streak.at_risk?(habit, timezone: @current_user.timezone || "Etc/UTC") do %>
                  <span
                    class="badge badge-warning badge-sm gap-1"
                    title="Last expected period was missed — don't miss this one"
                  >
                    <.icon name="hero-exclamation-triangle-micro" class="size-3" /> at risk
                  </span>
                <% end %>
              </div>
            </div>
            <.link
              navigate={~p"/habits/#{habit.id}/edit"}
              class="btn btn-xs btn-ghost"
              title="Edit"
            >
              <.icon name="hero-pencil-square-micro" class="size-4" />
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
