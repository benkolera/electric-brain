defmodule ElectricbrainWeb.TodoLive.Schedule do
  use ElectricbrainWeb, :live_view

  alias Electricbrain.Todos.Availability
  alias Electricbrain.Todos.Todo
  alias ElectricbrainWeb.CategoryPicker

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    todo = load_todo(id, user)

    {:ok,
     socket
     |> assign(:page_title, "Edit · #{todo.title}")
     |> assign(:todo, todo)
     |> CategoryPicker.assign(user)
     |> CategoryPicker.attach()
     |> assign(:picker_selected_id, todo.category_id)
     |> assign(:edit_form, edit_form(todo, user))
     |> assign(:timing_form, timing_form(todo, user))
     |> assign(:availability_form, availability_form(user))}
  end

  defp load_todo(id, user) do
    Todo
    |> Ash.get!(id, actor: user, load: [:availabilities])
  end

  defp edit_form(todo, user) do
    todo
    |> AshPhoenix.Form.for_update(:update, actor: user)
    |> to_form()
  end

  defp timing_form(todo, user) do
    todo
    |> AshPhoenix.Form.for_update(:update, actor: user)
    |> to_form()
  end

  defp availability_form(user) do
    Availability
    |> AshPhoenix.Form.for_create(:create, actor: user)
    |> to_form()
  end

  @impl true
  def handle_event("validate_edit", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.edit_form, params)
    {:noreply, assign(socket, edit_form: to_form(form))}
  end

  def handle_event("save_edit", %{"form" => params}, socket) do
    user = socket.assigns.current_user
    tz = user.timezone || "Etc/UTC"

    params =
      params
      |> Map.put("category_id", socket.assigns.picker_selected_id)
      |> maybe_convert_local_input("due_at", tz)
      |> maybe_convert_local_input("recurrence_anchor", tz)

    case AshPhoenix.Form.submit(socket.assigns.edit_form, params: params) do
      {:ok, todo} ->
        todo = load_todo(todo.id, user)

        {:noreply,
         socket
         |> assign(:todo, todo)
         |> assign(:edit_form, edit_form(todo, user))
         |> assign(:timing_form, timing_form(todo, user))
         |> put_flash(:info, "Saved")}

      {:error, form} ->
        {:noreply, assign(socket, edit_form: to_form(form))}
    end
  end

  @impl true
  def handle_event("validate_timing", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.timing_form, params)
    {:noreply, assign(socket, timing_form: to_form(form))}
  end

  @impl true
  def handle_event("save_timing", %{"form" => params}, socket) do
    user = socket.assigns.current_user

    case AshPhoenix.Form.submit(socket.assigns.timing_form, params: params) do
      {:ok, todo} ->
        todo = load_todo(todo.id, user)

        {:noreply,
         socket
         |> assign(:todo, todo)
         |> assign(:timing_form, timing_form(todo, user))
         |> put_flash(:info, "Saved")}

      {:error, form} ->
        {:noreply, assign(socket, timing_form: to_form(form))}
    end
  end

  def handle_event("add_availability", %{"form" => params}, socket) do
    user = socket.assigns.current_user
    params = Map.put(params, "todo_id", socket.assigns.todo.id)

    case AshPhoenix.Form.submit(socket.assigns.availability_form, params: params) do
      {:ok, _availability} ->
        todo = load_todo(socket.assigns.todo.id, user)

        {:noreply,
         socket
         |> assign(:todo, todo)
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

    todo = load_todo(socket.assigns.todo.id, user)
    {:noreply, assign(socket, todo: todo)}
  end

  defp day_name(1), do: "Mon"
  defp day_name(2), do: "Tue"
  defp day_name(3), do: "Wed"
  defp day_name(4), do: "Thu"
  defp day_name(5), do: "Fri"
  defp day_name(6), do: "Sat"
  defp day_name(7), do: "Sun"

  defp format_time(time), do: Calendar.strftime(time, "%H:%M")

  # Walks "YYYY-MM-DDTHH:MM" (datetime-local browser format) into a
  # UTC ISO8601 string by treating the input as a wall-clock time in
  # the user's tz. Without this, the value would round-trip through
  # the cast as if it were already UTC.
  defp maybe_convert_local_input(params, key, tz) do
    Map.update(params, key, nil, fn
      v when v in [nil, ""] -> v
      v -> local_input_to_utc(v, tz)
    end)
  end

  defp local_input_to_utc(value, tz) do
    case NaiveDateTime.from_iso8601(value <> ":00") do
      {:ok, naive} ->
        case DateTime.from_naive(naive, tz) do
          {:ok, dt} -> dt |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_iso8601()
          _ -> value
        end

      _ ->
        value
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div>
        <.link navigate={~p"/todos"} class="btn btn-sm btn-ghost">
          <.icon name="hero-arrow-left-micro" class="size-4" /> Back to todos
        </.link>
      </div>

      <div>
        <h1 class="font-display text-3xl font-bold tracking-tight text-secondary">
          {@todo.title}
        </h1>
        <p class="text-sm text-neutral-content/70">
          Edit the todo's details, scheduling cadence and availability windows.
        </p>
      </div>

      <.form
        for={@edit_form}
        id="edit-form"
        phx-change="validate_edit"
        phx-submit="save_edit"
        class="card bg-base-200 border border-base-300"
      >
        <div class="card-body space-y-3">
          <h2 class="card-title text-lg">Details</h2>

          <div class="grid sm:grid-cols-2 gap-3">
            <div class="sm:col-span-2">
              <label class="label"><span class="label-text text-xs">Title</span></label>
              <input
                type="text"
                name={@edit_form[:title].name}
                value={Phoenix.HTML.Form.normalize_value("text", @edit_form[:title].value)}
                class="input input-bordered w-full bg-base-100"
                required
                autocomplete="off"
              />
            </div>

            <div class="sm:col-span-2">
              <label class="label"><span class="label-text text-xs">Category</span></label>
              <CategoryPicker.picker
                categories={@categories}
                categories_by_id={@categories_by_id}
                selected_id={@picker_selected_id}
                query={@picker_query}
                open={@picker_open}
              />
            </div>

            <div>
              <label class="label"><span class="label-text text-xs">Priority</span></label>
              <select
                name={@edit_form[:priority].name}
                class="select select-bordered bg-base-100 w-full"
              >
                <option value="low" selected={@edit_form[:priority].value in [:low, "low"]}>
                  low
                </option>
                <option
                  value="medium"
                  selected={@edit_form[:priority].value in [nil, "", :medium, "medium"]}
                >
                  medium
                </option>
                <option value="high" selected={@edit_form[:priority].value in [:high, "high"]}>
                  high
                </option>
              </select>
            </div>

            <div>
              <label class="label"><span class="label-text text-xs">Due (optional)</span></label>
              <input
                type="datetime-local"
                name={@edit_form[:due_at].name}
                value={Phoenix.HTML.Form.normalize_value("datetime-local", @edit_form[:due_at].value)}
                class="input input-bordered w-full bg-base-100"
              />
            </div>

            <div>
              <label class="label"><span class="label-text text-xs">Repeats</span></label>
              <select
                name={@edit_form[:recurrence].name}
                class="select select-bordered bg-base-100 w-full"
              >
                <option
                  value="none"
                  selected={@edit_form[:recurrence].value in [nil, "", :none, "none"]}
                >
                  (once)
                </option>
                <option
                  value="weekly"
                  selected={@edit_form[:recurrence].value in [:weekly, "weekly"]}
                >
                  weekly
                </option>
                <option
                  value="biweekly"
                  selected={@edit_form[:recurrence].value in [:biweekly, "biweekly"]}
                >
                  every 2 weeks
                </option>
                <option
                  value="monthly"
                  selected={@edit_form[:recurrence].value in [:monthly, "monthly"]}
                >
                  monthly
                </option>
              </select>
            </div>

            <div>
              <label class="label flex-col items-start gap-0.5">
                <span class="label-text text-xs">First instance (anchor)</span>
                <span class="label-text-alt text-neutral-content/60 whitespace-normal">
                  required if repeating — sets day, day-of-month and time
                </span>
              </label>
              <input
                type="datetime-local"
                name={@edit_form[:recurrence_anchor].name}
                value={
                  Phoenix.HTML.Form.normalize_value(
                    "datetime-local",
                    @edit_form[:recurrence_anchor].value
                  )
                }
                class="input input-bordered w-full bg-base-100"
              />
            </div>
          </div>

          <div class="flex justify-end">
            <button type="submit" class="btn btn-primary">
              <.icon name="hero-check-micro" class="size-4" /> Save details
            </button>
          </div>
        </div>
      </.form>

      <.form
        for={@timing_form}
        id="timing-form"
        phx-change="validate_timing"
        phx-submit="save_timing"
        class="card bg-base-200 border border-base-300"
      >
        <div class="card-body space-y-3">
          <h2 class="card-title text-lg">Timing</h2>
          <div class="grid sm:grid-cols-[auto_auto_auto_1fr_auto] gap-3 items-end">
            <div>
              <label class="label">
                <span class="label-text text-xs">Duration (min)</span>
              </label>
              <input
                type="number"
                name={@timing_form[:duration_minutes].name}
                value={
                  Phoenix.HTML.Form.normalize_value("number", @timing_form[:duration_minutes].value)
                }
                min="0"
                class="input input-bordered w-24 bg-base-100"
                placeholder="—"
              />
            </div>
            <div>
              <label class="label">
                <span class="label-text text-xs">Buffer before (min)</span>
              </label>
              <input
                type="number"
                name={@timing_form[:buffer_before_minutes].name}
                value={
                  Phoenix.HTML.Form.normalize_value(
                    "number",
                    @timing_form[:buffer_before_minutes].value
                  )
                }
                min="0"
                class="input input-bordered w-24 bg-base-100"
              />
            </div>
            <div>
              <label class="label">
                <span class="label-text text-xs">Buffer after (min)</span>
              </label>
              <input
                type="number"
                name={@timing_form[:buffer_after_minutes].name}
                value={
                  Phoenix.HTML.Form.normalize_value(
                    "number",
                    @timing_form[:buffer_after_minutes].value
                  )
                }
                min="0"
                class="input input-bordered w-24 bg-base-100"
              />
            </div>
            <div></div>
            <button type="submit" class="btn btn-primary">
              <.icon name="hero-check-micro" class="size-4" /> Save
            </button>
          </div>
        </div>
      </.form>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body">
          <h2 class="card-title text-lg">Availability windows</h2>
          <p class="text-sm text-neutral-content/60">
            When this can be done. Empty means anytime.
          </p>

          <ul class="space-y-1 mt-2">
            <%= for a <- @todo.availabilities do %>
              <li class="flex items-center gap-3 py-1.5 px-2 rounded hover:bg-base-300/40">
                <span class="font-medium w-12">{day_name(a.day_of_week)}</span>
                <span class="text-sm text-neutral-content/80">
                  {format_time(a.start_time)} – {format_time(a.end_time)}
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
            <%= if @todo.availabilities == [] do %>
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
    </Layouts.app>
    """
  end
end
