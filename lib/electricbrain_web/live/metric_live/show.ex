defmodule ElectricbrainWeb.MetricLive.Show do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Metrics.Measurement
  alias Electricbrain.Metrics.Metric
  alias ElectricbrainWeb.CategoryPicker

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    metric = load_metric(id, user)

    {:ok,
     socket
     |> assign(:page_title, "Metric · #{metric.name}")
     |> assign(:metric, metric)
     |> CategoryPicker.assign(user)
     |> CategoryPicker.attach()
     |> assign(:picker_selected_id, metric.category_id)
     |> assign(:edit_form, edit_form(metric, user))
     |> assign(:measurement_form, measurement_form(metric, user))
     |> assign(:editing_measurement_id, nil)
     |> assign_chart_data()}
  end

  defp load_metric(id, user) do
    Metric
    |> Ash.get!(id,
      actor: user,
      load: [measurements: Ash.Query.sort(Measurement, recorded_at: :asc)]
    )
  end

  defp edit_form(metric, user) do
    metric
    |> AshPhoenix.Form.for_update(:update, actor: user)
    |> to_form()
  end

  defp measurement_form(metric, user) do
    Measurement
    |> AshPhoenix.Form.for_create(:create, actor: user, params: %{"metric_id" => metric.id})
    |> to_form()
  end

  @impl true
  def handle_event("validate_metric", %{"form" => params}, socket) do
    {:noreply,
     assign(socket, :edit_form, AshPhoenix.Form.validate(socket.assigns.edit_form, params))}
  end

  def handle_event("save_metric", %{"form" => params}, socket) do
    user = socket.assigns.current_user
    params = Map.put(params, "category_id", socket.assigns.picker_selected_id)

    case AshPhoenix.Form.submit(socket.assigns.edit_form, params: params) do
      {:ok, _metric} ->
        metric = load_metric(socket.assigns.metric.id, user)

        {:noreply,
         socket
         |> assign(:metric, metric)
         |> assign(:edit_form, edit_form(metric, user))
         |> put_flash(:info, "Saved")}

      {:error, form} ->
        {:noreply, assign(socket, edit_form: form)}
    end
  end

  def handle_event("validate_measurement", %{"form" => params}, socket) do
    {:noreply,
     assign(
       socket,
       :measurement_form,
       AshPhoenix.Form.validate(socket.assigns.measurement_form, params)
     )}
  end

  def handle_event("add_measurement", %{"form" => params}, socket) do
    user = socket.assigns.current_user
    tz = user.timezone || "Etc/UTC"

    params =
      params
      |> Map.put("metric_id", socket.assigns.metric.id)
      |> Map.update("recorded_at", nil, &local_input_to_utc(&1, tz))

    case AshPhoenix.Form.submit(socket.assigns.measurement_form, params: params) do
      {:ok, _measurement} ->
        metric = load_metric(socket.assigns.metric.id, user)

        {:noreply,
         socket
         |> assign(:metric, metric)
         |> assign(:measurement_form, measurement_form(metric, user))
         |> assign_chart_data()}

      {:error, form} ->
        {:noreply, assign(socket, measurement_form: form)}
    end
  end

  def handle_event("delete_measurement", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    Measurement
    |> Ash.get!(id, actor: user)
    |> Ash.destroy!(actor: user)

    metric = load_metric(socket.assigns.metric.id, user)

    {:noreply,
     socket
     |> assign(:metric, metric)
     |> assign_chart_data()}
  end

  # Convert "YYYY-MM-DDTHH:MM" (datetime-local) in the user's tz to UTC ISO.
  # Empty stays empty so the resource's recorded_at default fires.
  defp local_input_to_utc(value, _tz) when value in [nil, ""], do: value

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

  defp assign_chart_data(socket) do
    user = socket.assigns.current_user
    tz = user.timezone || "Etc/UTC"
    metric = socket.assigns.metric

    points =
      metric.measurements
      |> Enum.map(fn m ->
        %{
          t: DateTime.to_iso8601(m.recorded_at),
          v: Decimal.to_float(m.value)
        }
      end)

    chart =
      %{
        label: metric.name,
        unit: metric.unit,
        aggregation: metric.aggregation,
        timezone: tz,
        points: points
      }

    assign(socket, :chart, chart)
  end

  defp format_recorded_at(dt, tz) do
    dt |> DateTime.shift_zone!(tz || "Etc/UTC") |> Calendar.strftime("%Y-%m-%d %H:%M")
  end

  defp now_local_input(tz) do
    DateTime.utc_now()
    |> DateTime.shift_zone!(tz || "Etc/UTC")
    |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between">
        <div>
          <.link navigate={~p"/metrics"} class="text-xs text-neutral-content/60 hover:underline">
            ← All metrics
          </.link>
          <h1 class="font-display text-3xl font-bold tracking-tight text-accent drop-shadow-[0_0_12px_var(--color-accent)]">
            {@metric.name}
          </h1>
          <p class="text-sm text-neutral-content/70">
            {@metric.unit} · {if(@metric.aggregation == :sum,
              do: "summed per period",
              else: "latest value wins"
            )}
          </p>
        </div>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body p-4">
          <div
            id={"chart-#{@metric.id}"}
            phx-hook="MetricChart"
            phx-update="ignore"
            data-chart={Jason.encode!(@chart)}
            class="w-full h-64"
          >
          </div>
          <%= if @metric.measurements == [] do %>
            <p class="text-xs text-neutral-content/60 mt-2">
              No measurements yet — add one below.
            </p>
          <% end %>
        </div>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body p-4">
          <h2 class="card-title text-base">Add measurement</h2>
          <.form
            for={@measurement_form}
            id="add-measurement"
            phx-change="validate_measurement"
            phx-submit="add_measurement"
            class="grid sm:grid-cols-[1fr_1fr_auto] gap-2 items-end"
          >
            <div>
              <label class="label">
                <span class="label-text text-xs">Value ({@metric.unit})</span>
              </label>
              <input
                type="number"
                step="any"
                name={@measurement_form[:value].name}
                value={Phoenix.HTML.Form.normalize_value("number", @measurement_form[:value].value)}
                class="input input-bordered w-full bg-base-100"
                required
              />
            </div>
            <div>
              <label class="label">
                <span class="label-text text-xs">Recorded at (local, optional)</span>
              </label>
              <input
                type="datetime-local"
                name={@measurement_form[:recorded_at].name}
                value=""
                max={now_local_input(@current_user.timezone)}
                class="input input-bordered w-full bg-base-100 font-mono"
              />
            </div>
            <button type="submit" class="btn btn-primary">Record</button>
          </.form>
        </div>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body p-4">
          <h2 class="card-title text-base">History</h2>
          <%= if @metric.measurements == [] do %>
            <p class="text-sm text-neutral-content/60">No measurements yet.</p>
          <% else %>
            <ul class="divide-y divide-base-300/60">
              <%= for m <- Enum.reverse(@metric.measurements) do %>
                <li class="flex items-center gap-3 py-2 text-sm">
                  <span class="font-mono text-xs text-neutral-content/60 w-32 shrink-0">
                    {format_recorded_at(m.recorded_at, @current_user.timezone)}
                  </span>
                  <span class="font-medium flex-1">
                    {m.value} {@metric.unit}
                  </span>
                  <%= if m.completion_id do %>
                    <span class="badge badge-outline badge-xs">habit</span>
                  <% end %>
                  <button
                    phx-click="delete_measurement"
                    phx-value-id={m.id}
                    data-confirm="Delete this measurement?"
                    class="btn btn-xs btn-ghost text-error"
                    title="Delete"
                  >
                    <.icon name="hero-x-mark-micro" class="size-4" />
                  </button>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body p-4">
          <h2 class="card-title text-base">Edit metric</h2>
          <.form
            for={@edit_form}
            id="edit-metric"
            phx-change="validate_metric"
            phx-submit="save_metric"
            class="space-y-3"
          >
            <div class="grid sm:grid-cols-2 gap-3">
              <div class="sm:col-span-2">
                <label class="label"><span class="label-text text-xs">Name</span></label>
                <input
                  type="text"
                  name={@edit_form[:name].name}
                  value={Phoenix.HTML.Form.normalize_value("text", @edit_form[:name].value)}
                  class="input input-bordered w-full bg-base-100"
                  required
                  autocomplete="off"
                />
              </div>
              <div>
                <label class="label"><span class="label-text text-xs">Unit</span></label>
                <input
                  type="text"
                  name={@edit_form[:unit].name}
                  value={Phoenix.HTML.Form.normalize_value("text", @edit_form[:unit].value)}
                  class="input input-bordered w-full bg-base-100"
                  required
                  autocomplete="off"
                />
              </div>
              <div>
                <label class="label"><span class="label-text text-xs">Aggregation</span></label>
                <select
                  name={@edit_form[:aggregation].name}
                  class="select select-bordered bg-base-100 w-full"
                >
                  <option value="point" selected={@edit_form[:aggregation].value in [:point, "point"]}>
                    Point-in-time (latest wins)
                  </option>
                  <option value="sum" selected={@edit_form[:aggregation].value in [:sum, "sum"]}>
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
                  name={@edit_form[:group_name].name}
                  value={Phoenix.HTML.Form.normalize_value("text", @edit_form[:group_name].value)}
                  class="input input-bordered w-full bg-base-100"
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
            </div>
            <div class="flex justify-end">
              <button type="submit" class="btn btn-primary">Save</button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
