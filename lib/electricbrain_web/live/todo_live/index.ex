defmodule ElectricbrainWeb.TodoLive.Index do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Todos.Todo
  alias ElectricbrainWeb.CategoryPicker

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Todos")
     |> CategoryPicker.assign(user)
     |> CategoryPicker.attach()
     |> assign(:form, new_form(user))
     |> assign(:todos, list_todos(user))}
  end

  defp new_form(user) do
    Todo
    |> AshPhoenix.Form.for_create(:create, actor: user)
    |> to_form()
  end

  defp list_todos(user) do
    Todo
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!(actor: user)
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
      {:ok, _todo} ->
        {:noreply,
         socket
         |> assign(:form, new_form(user))
         |> CategoryPicker.reset()
         |> assign(:todos, list_todos(user))
         |> put_flash(:info, "Todo added")}

      {:error, form} ->
        {:noreply, assign(socket, form: to_form(form))}
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    Todo
    |> Ash.get!(id, actor: user)
    |> Ash.Changeset.for_update(:toggle, %{}, actor: user)
    |> Ash.update!()

    {:noreply, assign(socket, todos: list_todos(user))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    Todo
    |> Ash.get!(id, actor: user)
    |> Ash.destroy!(actor: user)

    {:noreply, assign(socket, todos: list_todos(user))}
  end

  defp priority_badge(:high), do: "badge badge-error badge-sm"
  defp priority_badge(:medium), do: "badge badge-warning badge-sm"
  defp priority_badge(:low), do: "badge badge-ghost badge-sm"
  defp priority_badge(_), do: "badge badge-ghost badge-sm"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div>
        <h1 class="font-display text-3xl font-bold tracking-tight text-secondary drop-shadow-[0_0_12px_var(--color-secondary)]">
          Todos
        </h1>
        <p class="text-sm text-neutral-content/70">
          Keep the brain charged with a punch-list.
        </p>
      </div>

      <.form
        for={@form}
        id="todo-form"
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
              placeholder="Wire up the synapses…"
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
              <span class="label-text text-xs">Priority</span>
            </label>
            <select
              name={@form[:priority].name}
              class="select select-bordered bg-base-100"
            >
              <option value="low">low</option>
              <option value="medium" selected>medium</option>
              <option value="high">high</option>
            </select>
          </div>
          <div>
            <label class="label">
              <span class="label-text text-xs">Due</span>
            </label>
            <input
              type="datetime-local"
              name={@form[:due_at].name}
              value={Phoenix.HTML.Form.normalize_value("datetime-local", @form[:due_at].value)}
              class="input input-bordered bg-base-100"
            />
          </div>
          <button type="submit" class="btn btn-primary">
            <.icon name="hero-plus-micro" class="size-4" /> Add
          </button>
        </div>
      </.form>

      <ul class="space-y-2">
        <%= for todo <- @todos do %>
          <li class={[
            "flex items-center gap-3 p-3 bg-base-200 border border-base-300 rounded-box",
            todo.status == :done && "opacity-60"
          ]}>
            <input
              type="checkbox"
              checked={todo.status == :done}
              phx-click="toggle"
              phx-value-id={todo.id}
              class="checkbox checkbox-primary"
            />
            <div class="flex-1 min-w-0">
              <p class={[
                "font-medium truncate",
                todo.status == :done && "line-through text-neutral-content/60"
              ]}>
                {todo.title}
              </p>
              <div class="flex flex-wrap items-center gap-2 text-xs text-neutral-content/60 mt-0.5">
                <%= if cat = Map.get(@categories_by_id, todo.category_id) do %>
                  <span class="badge badge-outline badge-sm">
                    {CategoryPicker.breadcrumb(cat.path)}
                  </span>
                <% end %>
                <span class={priority_badge(todo.priority)}>{todo.priority}</span>
                <%= if todo.due_at do %>
                  <span class="inline-flex items-center gap-1">
                    <.icon name="hero-clock-micro" class="size-3" />
                    {Calendar.strftime(todo.due_at, "%Y-%m-%d %H:%M")}
                  </span>
                <% end %>
              </div>
            </div>
            <.link
              navigate={~p"/todos/#{todo.id}/schedule"}
              class="btn btn-xs btn-ghost"
              title="Schedule"
            >
              <.icon name="hero-calendar-micro" class="size-4" />
            </.link>
            <button
              phx-click="delete"
              phx-value-id={todo.id}
              data-confirm="Delete this todo?"
              class="btn btn-xs btn-ghost text-error"
            >
              <.icon name="hero-x-mark-micro" class="size-4" />
            </button>
          </li>
        <% end %>
        <%= if @todos == [] do %>
          <li class="text-center py-12 text-neutral-content/60">
            No todos yet. Add one above.
          </li>
        <% end %>
      </ul>
    </Layouts.app>
    """
  end
end
