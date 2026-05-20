defmodule ElectricbrainWeb.TodoLive.Schedule do
  use ElectricbrainWeb, :live_view

  alias Electricbrain.Todos.Availability
  alias Electricbrain.Todos.Todo

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    todo = load_todo(id, user)

    {:ok,
     socket
     |> assign(:page_title, "Schedule · #{todo.title}")
     |> assign(:todo, todo)
     |> assign(:timing_form, timing_form(todo, user))
     |> assign(:availability_form, availability_form(user))}
  end

  defp load_todo(id, user) do
    Todo
    |> Ash.get!(id, actor: user, load: [:availabilities])
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
        <h1 class="font-display text-3xl font-bold tracking-tight text-secondary drop-shadow-[0_0_12px_var(--color-secondary)]">
          {@todo.title}
        </h1>
        <p class="text-sm text-neutral-content/70">
          When can this be done and how much calendar space does it take.
        </p>
      </div>

      <.form
        for={@timing_form}
        id="timing-form"
        phx-change="validate_timing"
        phx-submit="save_timing"
        class="card bg-base-200 border border-base-300"
      >
        <div class="card-body grid sm:grid-cols-[auto_auto_auto_1fr_auto] gap-3 items-end">
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
                Phoenix.HTML.Form.normalize_value("number", @timing_form[:buffer_after_minutes].value)
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
