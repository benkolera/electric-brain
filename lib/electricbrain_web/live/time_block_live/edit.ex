defmodule ElectricbrainWeb.TimeBlockLive.Edit do
  use ElectricbrainWeb, :live_view

  alias Electricbrain.TimeBlocks.Availability
  alias Electricbrain.TimeBlocks.TimeBlock
  alias ElectricbrainWeb.CategoryPicker

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    block = load_block(id, user)

    {:ok,
     socket
     |> assign(:page_title, "Edit · #{block.title}")
     |> assign(:block, block)
     |> CategoryPicker.assign(user)
     |> CategoryPicker.attach()
     |> assign(:picker_selected_id, block.category_id)
     |> assign(:edit_form, edit_form(block, user))
     |> assign(:availability_form, availability_form(user))}
  end

  defp load_block(id, user) do
    TimeBlock
    |> Ash.get!(id, actor: user, load: [:availabilities])
  end

  defp edit_form(block, user) do
    block
    |> AshPhoenix.Form.for_update(:update, actor: user)
    |> to_form()
  end

  defp availability_form(user) do
    Availability
    |> AshPhoenix.Form.for_create(:create, actor: user)
    |> to_form()
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.edit_form, params)
    {:noreply, assign(socket, edit_form: to_form(form))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    user = socket.assigns.current_user
    params = Map.put(params, "category_id", socket.assigns.picker_selected_id)

    case AshPhoenix.Form.submit(socket.assigns.edit_form, params: params) do
      {:ok, block} ->
        block = load_block(block.id, user)

        {:noreply,
         socket
         |> assign(:block, block)
         |> assign(:edit_form, edit_form(block, user))
         |> put_flash(:info, "Saved")}

      {:error, form} ->
        {:noreply, assign(socket, edit_form: to_form(form))}
    end
  end

  def handle_event("add_availability", %{"form" => params}, socket) do
    user = socket.assigns.current_user
    params = Map.put(params, "time_block_id", socket.assigns.block.id)

    case AshPhoenix.Form.submit(socket.assigns.availability_form, params: params) do
      {:ok, _availability} ->
        block = load_block(socket.assigns.block.id, user)

        {:noreply,
         socket
         |> assign(:block, block)
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

    block = load_block(socket.assigns.block.id, user)
    {:noreply, assign(socket, block: block)}
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

  defp weekly_total(%{availabilities: avails}) do
    Enum.reduce(avails, 0, fn a, acc ->
      acc + Availability.duration_minutes(a) * Availability.occurrences_per_week(a)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div>
        <.link navigate={~p"/time-blocks"} class="btn btn-sm btn-ghost">
          <.icon name="hero-arrow-left-micro" class="size-4" /> Back to time blocks
        </.link>
      </div>

      <div>
        <h1 class="font-display text-3xl font-bold tracking-tight text-accent">
          {@block.title}
        </h1>
      </div>

      <.form
        for={@edit_form}
        id="edit-form"
        phx-change="validate"
        phx-submit="save"
        class="card bg-base-200 border border-base-300"
      >
        <div class="card-body space-y-3">
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
              <label class="label">
                <span class="label-text text-xs">Weekly target (min)</span>
              </label>
              <input
                type="number"
                name={@edit_form[:weekly_target_minutes].name}
                value={
                  Phoenix.HTML.Form.normalize_value(
                    "number",
                    @edit_form[:weekly_target_minutes].value
                  )
                }
                min="0"
                class="input input-bordered w-full bg-base-100"
                placeholder="e.g. 3360 for 56h sleep"
              />
            </div>

            <div>
              <label class="label">
                <span class="label-text text-xs">Target direction</span>
              </label>
              <select
                name={@edit_form[:target_kind].name}
                class="select select-bordered bg-base-100 w-full"
              >
                <option value="" selected={@edit_form[:target_kind].value in [nil, ""]}>
                  (none)
                </option>
                <option
                  value="at_least"
                  selected={@edit_form[:target_kind].value in [:at_least, "at_least"]}
                >
                  at least
                </option>
                <option
                  value="at_most"
                  selected={@edit_form[:target_kind].value in [:at_most, "at_most"]}
                >
                  at most
                </option>
              </select>
            </div>

            <div>
              <label class="label">
                <span class="label-text text-xs">Duration (min)</span>
              </label>
              <input
                type="number"
                name={@edit_form[:duration_minutes].name}
                value={
                  Phoenix.HTML.Form.normalize_value(
                    "number",
                    @edit_form[:duration_minutes].value
                  )
                }
                min="0"
                class="input input-bordered w-full bg-base-100"
                placeholder="Optional"
              />
            </div>

            <div>
              <label class="label">
                <span class="label-text text-xs">Buffer before (min)</span>
              </label>
              <input
                type="number"
                name={@edit_form[:buffer_before_minutes].name}
                value={
                  Phoenix.HTML.Form.normalize_value(
                    "number",
                    @edit_form[:buffer_before_minutes].value
                  ) || 0
                }
                min="0"
                class="input input-bordered w-full bg-base-100"
              />
            </div>

            <div>
              <label class="label">
                <span class="label-text text-xs">Buffer after (min)</span>
              </label>
              <input
                type="number"
                name={@edit_form[:buffer_after_minutes].name}
                value={
                  Phoenix.HTML.Form.normalize_value(
                    "number",
                    @edit_form[:buffer_after_minutes].value
                  ) || 0
                }
                min="0"
                class="input input-bordered w-full bg-base-100"
              />
            </div>
          </div>

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
            <h2 class="card-title text-lg">Availability windows</h2>
            <span class="text-sm">
              <span class="text-neutral-content/60">Planned per week:</span>
              <span class="font-mono font-medium text-accent ml-1">
                {format_hhmm(weekly_total(@block))}
              </span>
            </span>
          </div>
          <p class="text-sm text-neutral-content/60">
            Each window is auto-placed onto the planner once per occurrence. End before start means it wraps past midnight.
          </p>

          <ul class="space-y-1 mt-2">
            <%= for a <- @block.availabilities do %>
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
                  data-confirm="Remove this availability window?"
                  class="btn btn-xs btn-ghost text-error"
                >
                  <.icon name="hero-x-mark-micro" class="size-3.5" />
                </button>
              </li>
            <% end %>
            <%= if @block.availabilities == [] do %>
              <li class="text-sm text-neutral-content/60 py-2">
                No windows yet — add one below.
              </li>
            <% end %>
          </ul>

          <.form
            for={@availability_form}
            id="add-availability"
            phx-submit="add_availability"
            class="flex flex-wrap items-end gap-2 mt-3 pt-3 border-t border-base-300"
          >
            <div>
              <label class="label"><span class="label-text text-xs">Day</span></label>
              <select
                name={@availability_form[:day_of_week].name}
                class="select select-bordered bg-base-100"
              >
                <option value="">Every day</option>
                <%= for {label, num} <- [{"Mon", 1}, {"Tue", 2}, {"Wed", 3}, {"Thu", 4}, {"Fri", 5}, {"Sat", 6}, {"Sun", 7}] do %>
                  <option value={num}>{label}</option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="label"><span class="label-text text-xs">Start</span></label>
              <input
                type="time"
                name={@availability_form[:start_time].name}
                class="input input-bordered bg-base-100"
                required
              />
            </div>
            <div>
              <label class="label"><span class="label-text text-xs">End</span></label>
              <input
                type="time"
                name={@availability_form[:end_time].name}
                class="input input-bordered bg-base-100"
                required
              />
            </div>
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
