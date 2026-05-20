defmodule ElectricbrainWeb.MetricLive.Index do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Metrics.Metric
  alias ElectricbrainWeb.CategoryPicker

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Metrics")
     |> CategoryPicker.assign(user)
     |> CategoryPicker.attach()
     |> assign(:create_open, false)
     |> assign(:form, new_form(user))
     |> assign(:metrics, list_metrics(user))}
  end

  defp new_form(user) do
    Metric
    |> AshPhoenix.Form.for_create(:create, actor: user)
    |> to_form()
  end

  defp list_metrics(user) do
    Metric
    |> Ash.Query.sort(group_name: :asc, name: :asc)
    |> Ash.read!(actor: user)
  end

  @impl true
  def handle_event("toggle_create", _params, socket) do
    user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(:create_open, !socket.assigns.create_open)
     |> assign(:form, new_form(user))}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    user = socket.assigns.current_user
    params = Map.put(params, "category_id", socket.assigns.picker_selected_id)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, metric} ->
        {:noreply,
         socket
         |> assign(:create_open, false)
         |> assign(:form, new_form(user))
         |> assign(:metrics, list_metrics(user))
         |> push_navigate(to: ~p"/metrics/#{metric.id}")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Metric
         |> Ash.get!(id, actor: user)
         |> Ash.destroy(actor: user) do
      :ok ->
        {:noreply, assign(socket, :metrics, list_metrics(user))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete that metric")}
    end
  end

  defp grouped(metrics) do
    metrics
    |> Enum.group_by(&(&1.group_name || &1.name))
    |> Enum.sort_by(fn {label, _} -> label end)
  end

  defp aggregation_label(:point), do: "latest"
  defp aggregation_label(:sum), do: "summed"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-accent drop-shadow-[0_0_12px_var(--color-accent)]">
            Metrics
          </h1>
          <p class="text-sm text-neutral-content/70">
            Track values over time — weight, lifts, water, drinks. Attach to habits to capture on completion.
          </p>
        </div>
        <button type="button" phx-click="toggle_create" class="btn btn-primary btn-sm">
          <.icon name="hero-plus-micro" class="size-4" /> Add metric
        </button>
      </div>

      <%= if @create_open do %>
        <.form
          for={@form}
          id="create-metric"
          phx-change="validate"
          phx-submit="save"
          class="card bg-base-200 border border-base-300"
        >
          <div class="card-body space-y-3">
            <div class="grid sm:grid-cols-2 gap-3">
              <div class="sm:col-span-2">
                <label class="label"><span class="label-text text-xs">Name</span></label>
                <input
                  type="text"
                  name={@form[:name].name}
                  value={Phoenix.HTML.Form.normalize_value("text", @form[:name].value)}
                  class="input input-bordered w-full bg-base-100"
                  placeholder="Weight, Deadlift 1RM, Water, Drinks"
                  required
                  autocomplete="off"
                />
              </div>

              <div>
                <label class="label"><span class="label-text text-xs">Unit</span></label>
                <input
                  type="text"
                  name={@form[:unit].name}
                  value={Phoenix.HTML.Form.normalize_value("text", @form[:unit].value)}
                  class="input input-bordered w-full bg-base-100"
                  placeholder="kg, L, kcal, count"
                  required
                  autocomplete="off"
                />
              </div>

              <div>
                <label class="label"><span class="label-text text-xs">Aggregation</span></label>
                <select
                  name={@form[:aggregation].name}
                  class="select select-bordered bg-base-100 w-full"
                >
                  <option
                    value="point"
                    selected={@form[:aggregation].value in [nil, "", :point, "point"]}
                  >
                    Point-in-time (latest wins)
                  </option>
                  <option value="sum" selected={@form[:aggregation].value in [:sum, "sum"]}>
                    Summed per period
                  </option>
                </select>
              </div>

              <div>
                <label class="label">
                  <span class="label-text text-xs">Group (optional)</span>
                </label>
                <input
                  type="text"
                  name={@form[:group_name].name}
                  value={Phoenix.HTML.Form.normalize_value("text", @form[:group_name].value)}
                  class="input input-bordered w-full bg-base-100"
                  placeholder="e.g. Deadlift — share with 1RM/3RM/8RM"
                  autocomplete="off"
                />
              </div>

              <div>
                <label class="label"><span class="label-text text-xs">Category</span></label>
                <CategoryPicker.picker
                  categories={@categories}
                  categories_by_id={@categories_by_id}
                  selected_id={@picker_selected_id}
                  query={@picker_query}
                  open={@picker_open}
                />
              </div>
            </div>

            <div class="flex justify-end gap-2">
              <button type="button" phx-click="toggle_create" class="btn btn-ghost">Cancel</button>
              <button type="submit" class="btn btn-primary">Create</button>
            </div>
          </div>
        </.form>
      <% end %>

      <%= if @metrics == [] do %>
        <div class="text-center py-12 text-neutral-content/60">
          No metrics yet. Add one above.
        </div>
      <% else %>
        <%= for {label, items} <- grouped(@metrics) do %>
          <div class="card bg-base-200 border border-base-300">
            <div class="card-body p-4">
              <h2 class="card-title text-base">{label}</h2>
              <ul class="divide-y divide-base-300/60">
                <%= for m <- items do %>
                  <li class="flex items-center gap-3 py-2">
                    <div class="flex-1 min-w-0">
                      <.link navigate={~p"/metrics/#{m.id}"} class="font-medium hover:underline">
                        {m.name}
                      </.link>
                      <p class="text-xs text-neutral-content/60">
                        {m.unit} · {aggregation_label(m.aggregation)}
                      </p>
                    </div>
                    <button
                      phx-click="delete"
                      phx-value-id={m.id}
                      data-confirm={"Delete metric \"#{m.name}\" and all its measurements?"}
                      class="btn btn-xs btn-ghost text-error"
                      title="Delete"
                    >
                      <.icon name="hero-x-mark-micro" class="size-4" />
                    </button>
                  </li>
                <% end %>
              </ul>
            </div>
          </div>
        <% end %>
      <% end %>
    </Layouts.app>
    """
  end
end
