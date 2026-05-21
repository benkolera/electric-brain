defmodule ElectricbrainWeb.TimeBlockLive.Index do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.TimeBlocks.Availability
  alias Electricbrain.TimeBlocks.TimeBlock
  alias ElectricbrainWeb.CategoryPicker

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Time blocks")
     |> CategoryPicker.assign(user)
     |> CategoryPicker.attach()
     |> assign(:create_open, false)
     |> assign(:form, new_form(user))
     |> assign(:blocks, list_blocks(user))}
  end

  defp new_form(user) do
    TimeBlock
    |> AshPhoenix.Form.for_create(:create, actor: user)
    |> to_form()
  end

  defp list_blocks(user) do
    TimeBlock
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.load(:availabilities)
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
      {:ok, _block} ->
        {:noreply,
         socket
         |> assign(:create_open, false)
         |> assign(:form, new_form(user))
         |> assign(:blocks, list_blocks(user))}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case TimeBlock
         |> Ash.get!(id, actor: user)
         |> Ash.destroy(actor: user) do
      :ok ->
        {:noreply, assign(socket, :blocks, list_blocks(user))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete that time block")}
    end
  end

  # Sum of (availability duration × occurrences) across the block's
  # availability windows, in minutes. Drives the "planned per week"
  # summary in the row.
  defp weekly_minutes(%{availabilities: avails}) do
    Enum.reduce(avails, 0, fn a, acc ->
      acc + Availability.duration_minutes(a) * Availability.occurrences_per_week(a)
    end)
  end

  defp format_hhmm(minutes) when is_integer(minutes) and minutes >= 0 do
    h = div(minutes, 60)
    m = rem(minutes, 60)
    :io_lib.format("~2..0B:~2..0B", [h, m]) |> IO.iodata_to_binary()
  end

  defp target_summary(%{weekly_target_minutes: nil}), do: nil

  defp target_summary(%{weekly_target_minutes: mins, target_kind: kind}) do
    label =
      case kind do
        :at_least -> "≥"
        :at_most -> "≤"
        _ -> "≈"
      end

    "#{label} #{format_hhmm(mins)} / week"
  end

  defp drift_class(_block, _planned) do
    # Placeholder for the future "actual vs target" UI; once entries
    # tally per-block we'll colour this badge red/green/amber. For now
    # we just show the planned total without comparison styling.
    "badge badge-ghost badge-sm"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-accent drop-shadow-[0_0_12px_var(--color-accent)]">
            Time blocks
          </h1>
          <p class="text-sm text-neutral-content/70">
            Recurring tracked time — Sleep, Work, etc. Auto-placed onto the planner from availability windows.
          </p>
        </div>
        <button type="button" phx-click="toggle_create" class="btn btn-primary btn-sm">
          <.icon name="hero-plus-micro" class="size-4" /> Add time block
        </button>
      </div>

      <%= if @create_open do %>
        <.form
          for={@form}
          id="create-time-block"
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
                  name={@form[:title].name}
                  value={Phoenix.HTML.Form.normalize_value("text", @form[:title].value)}
                  class="input input-bordered w-full bg-base-100"
                  placeholder="Sleep, Work, Deep work…"
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
                  name={@form[:weekly_target_minutes].name}
                  value={
                    Phoenix.HTML.Form.normalize_value(
                      "number",
                      @form[:weekly_target_minutes].value
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
                  name={@form[:target_kind].name}
                  class="select select-bordered bg-base-100 w-full"
                >
                  <option value="" selected={@form[:target_kind].value in [nil, ""]}>
                    (none)
                  </option>
                  <option
                    value="at_least"
                    selected={@form[:target_kind].value in [:at_least, "at_least"]}
                  >
                    at least
                  </option>
                  <option
                    value="at_most"
                    selected={@form[:target_kind].value in [:at_most, "at_most"]}
                  >
                    at most
                  </option>
                </select>
              </div>
            </div>

            <div class="flex justify-end gap-2">
              <button type="button" phx-click="toggle_create" class="btn btn-ghost">Cancel</button>
              <button type="submit" class="btn btn-primary">Save</button>
            </div>
            <p class="text-xs text-neutral-content/60">
              Set availability windows after creating, on the edit page.
            </p>
          </div>
        </.form>
      <% end %>

      <ul class="space-y-2">
        <%= for block <- @blocks do %>
          <li class="flex items-center gap-3 p-3 bg-base-200 border border-base-300 rounded-box">
            <.link
              navigate={~p"/time-blocks/#{block.id}/edit"}
              class="flex-1 min-w-0 flex items-center gap-3"
            >
              <div class="flex-1 min-w-0">
                <p class="font-medium truncate">{block.title}</p>
                <div class="flex flex-wrap items-center gap-2 text-xs text-neutral-content/60 mt-0.5">
                  <%= if cat = Map.get(@categories_by_id, block.category_id) do %>
                    <span class="badge badge-outline badge-sm">
                      {CategoryPicker.breadcrumb(cat.path)}
                    </span>
                  <% end %>
                  <span class={drift_class(block, weekly_minutes(block))}>
                    Planned {format_hhmm(weekly_minutes(block))} / week
                  </span>
                  <%= if summary = target_summary(block) do %>
                    <span class="badge badge-info badge-outline badge-sm">{summary}</span>
                  <% end %>
                </div>
              </div>
            </.link>
            <.link
              navigate={~p"/time-blocks/#{block.id}/edit"}
              class="btn btn-xs btn-ghost"
              title="Edit"
            >
              <.icon name="hero-pencil-square-micro" class="size-4" />
            </.link>
            <button
              phx-click="delete"
              phx-value-id={block.id}
              data-confirm={"Delete \"#{block.title}\" and its availability windows?"}
              class="btn btn-xs btn-ghost text-error"
            >
              <.icon name="hero-x-mark-micro" class="size-4" />
            </button>
          </li>
        <% end %>
        <%= if @blocks == [] do %>
          <li class="text-center py-12 text-neutral-content/60">
            No time blocks yet. Add one above.
          </li>
        <% end %>
      </ul>
    </Layouts.app>
    """
  end
end
