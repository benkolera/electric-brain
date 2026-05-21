defmodule ElectricbrainWeb.PlannerLive.Review do
  @moduledoc """
  Weekly reflection page — Atomic Habits ch. 20. One row per habit for
  the current week with: completion stats, last week's reflection (for
  context), and editable notes + 1-5 difficulty rating for this week.
  Difficulty 1 = too easy, 3 = just right, 5 = too hard (the Goldilocks
  signal from ch. 19).
  """

  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Categories
  alias Electricbrain.Categories.Colors
  alias Electricbrain.Habits.Habit
  alias Electricbrain.Habits.Reflection

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    categories = Categories.list_with_paths(user)
    monday = monday_in_tz(DateTime.utc_now(), user.timezone)

    {:ok,
     socket
     |> assign(:page_title, "Weekly review")
     |> assign(:timezone, user.timezone)
     |> assign(:categories_by_id, Map.new(categories, &{&1.id, &1}))
     |> assign(:week_start, monday)
     |> load_week()}
  end

  defp load_week(socket) do
    user = socket.assigns.current_user
    week_start = socket.assigns.week_start
    timezone = socket.assigns.timezone

    habits =
      Habit
      |> Ash.Query.sort(inserted_at: :asc)
      |> Ash.Query.load(:completions)
      |> Ash.read!(actor: user)

    reflections_this_week = reflections_for(user, week_start)
    reflections_last_week = reflections_for(user, Date.add(week_start, -7))

    rows =
      Enum.map(habits, fn habit ->
        this_week = Map.get(reflections_this_week, habit.id)
        last_week = Map.get(reflections_last_week, habit.id)

        %{
          habit: habit,
          completions_this_week:
            count_completions_in_week(habit.completions, week_start, timezone),
          form: reflection_form(habit, week_start, this_week, user),
          last_week: last_week
        }
      end)

    assign(socket, :rows, rows)
  end

  defp reflections_for(user, week_start) do
    Reflection
    |> Ash.Query.filter(week_start == ^week_start)
    |> Ash.read!(actor: user)
    |> Map.new(&{&1.habit_id, &1})
  end

  defp reflection_form(habit, week_start, existing, user) do
    case existing do
      nil ->
        Reflection
        |> AshPhoenix.Form.for_create(:upsert,
          actor: user,
          forms: [],
          params: %{
            "habit_id" => habit.id,
            "week_start" => Date.to_iso8601(week_start)
          }
        )
        |> to_form()

      %Reflection{} = r ->
        Reflection
        |> AshPhoenix.Form.for_create(:upsert,
          actor: user,
          forms: [],
          params: %{
            "habit_id" => habit.id,
            "week_start" => Date.to_iso8601(week_start),
            "notes" => r.notes,
            "difficulty" => r.difficulty
          }
        )
        |> to_form()
    end
  end

  defp count_completions_in_week(completions, week_start, timezone) do
    week_end_date = Date.add(week_start, 7)

    week_start_utc =
      week_start
      |> DateTime.new!(~T[00:00:00], timezone)
      |> DateTime.shift_zone!("Etc/UTC")

    week_end_utc =
      week_end_date
      |> DateTime.new!(~T[00:00:00], timezone)
      |> DateTime.shift_zone!("Etc/UTC")

    Enum.count(completions, fn c ->
      not is_nil(c.completed_at) and
        DateTime.compare(c.completed_at, week_start_utc) != :lt and
        DateTime.compare(c.completed_at, week_end_utc) == :lt
    end)
  end

  defp monday_in_tz(now_utc, timezone) do
    local = DateTime.shift_zone!(now_utc, timezone)
    date = DateTime.to_date(local)
    days_back = Date.day_of_week(date) - 1
    Date.add(date, -days_back)
  end

  @impl true
  def handle_event("prev_week", _params, socket) do
    {:noreply,
     socket
     |> assign(:week_start, Date.add(socket.assigns.week_start, -7))
     |> load_week()}
  end

  def handle_event("next_week", _params, socket) do
    {:noreply,
     socket
     |> assign(:week_start, Date.add(socket.assigns.week_start, 7))
     |> load_week()}
  end

  def handle_event("save_reflection", %{"habit_id" => habit_id, "form" => params}, socket) do
    row = Enum.find(socket.assigns.rows, &(&1.habit.id == habit_id))

    params =
      params
      |> Map.put("habit_id", habit_id)
      |> Map.put("week_start", Date.to_iso8601(socket.assigns.week_start))

    case AshPhoenix.Form.submit(row.form, params: params) do
      {:ok, _reflection} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved reflection for #{row.habit.title}")
         |> load_week()}

      {:error, form} ->
        rows =
          Enum.map(socket.assigns.rows, fn r ->
            if r.habit.id == habit_id, do: %{r | form: to_form(form)}, else: r
          end)

        {:noreply, assign(socket, :rows, rows)}
    end
  end

  defp category_color_hex(habit, categories_by_id) do
    Colors.hex_for(Colors.resolve_id(categories_by_id, habit.category_id))
  end

  defp difficulty_label(nil), do: "—"
  defp difficulty_label(1), do: "Too easy"
  defp difficulty_label(2), do: "Easy"
  defp difficulty_label(3), do: "Just right"
  defp difficulty_label(4), do: "Hard"
  defp difficulty_label(5), do: "Too hard"

  defp progress_class(completions, %{min_count: min}) when is_integer(min) do
    cond do
      completions >= min -> "badge badge-success badge-sm"
      completions == 0 -> "badge badge-error badge-sm"
      true -> "badge badge-warning badge-sm"
    end
  end

  defp progress_class(_, _), do: "badge badge-ghost badge-sm"

  defp period_label(:day), do: "/ day"
  defp period_label(:week), do: "/ week"
  defp period_label(:month), do: "/ month"
  defp period_label(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-success">
            Weekly review
          </h1>
          <p class="text-sm text-neutral-content/70">
            Week of {Date.to_iso8601(@week_start)} — what worked, what to adjust.
          </p>
        </div>

        <div class="flex items-center gap-2">
          <.link navigate={~p"/plan"} class="btn btn-sm btn-ghost">
            <.icon name="hero-arrow-left-micro" class="size-4" /> Back to plan
          </.link>
          <button type="button" phx-click="prev_week" class="btn btn-sm btn-ghost">
            <.icon name="hero-chevron-left-micro" class="size-4" /> Prev
          </button>
          <button type="button" phx-click="next_week" class="btn btn-sm btn-ghost">
            Next <.icon name="hero-chevron-right-micro" class="size-4" />
          </button>
        </div>
      </div>

      <%= if @rows == [] do %>
        <p class="text-neutral-content/60">
          No habits yet. Add some on the
          <.link navigate={~p"/habits"} class="link link-primary">Habits page</.link>
          first.
        </p>
      <% end %>

      <ul class="space-y-3">
        <%= for row <- @rows do %>
          <li class="card bg-base-200 border border-base-300">
            <div class="card-body p-4">
              <div class="flex items-center gap-2 flex-wrap">
                <span
                  class="size-3 rounded-full border border-neutral-content/30"
                  style={"background:#{category_color_hex(row.habit, @categories_by_id)}"}
                >
                </span>
                <h2 class="card-title text-base">{row.habit.title}</h2>
                <span class={progress_class(row.completions_this_week, row.habit)}>
                  {row.completions_this_week} / {row.habit.min_count || "—"} {period_label(
                    row.habit.period
                  )}
                </span>
                <%= if row.habit.identity_statement do %>
                  <span
                    class="text-xs text-neutral-content/60 italic ml-2"
                    title="Identity statement"
                  >
                    "{row.habit.identity_statement}"
                  </span>
                <% end %>
              </div>

              <%= if row.last_week do %>
                <details class="text-xs text-neutral-content/60 mt-1">
                  <summary class="cursor-pointer">
                    Last week's reflection
                    <%= if row.last_week.difficulty do %>
                      · {difficulty_label(row.last_week.difficulty)}
                    <% end %>
                  </summary>
                  <p class="mt-1 whitespace-pre-wrap pl-3 border-l-2 border-base-300">
                    {row.last_week.notes || "(no notes)"}
                  </p>
                </details>
              <% end %>

              <.form
                for={row.form}
                phx-submit="save_reflection"
                class="mt-2 space-y-2"
              >
                <input type="hidden" name="habit_id" value={row.habit.id} />

                <label class="label py-0">
                  <span class="label-text text-xs">What worked / what to adjust</span>
                </label>
                <textarea
                  name={row.form[:notes].name}
                  rows="3"
                  class="textarea textarea-bordered w-full bg-base-100"
                  placeholder="One or two sentences — patterns, blockers, small adjustments to try."
                ><%= Phoenix.HTML.Form.normalize_value("textarea", row.form[:notes].value) %></textarea>

                <div class="flex items-center gap-2 flex-wrap">
                  <span class="label-text text-xs">Difficulty:</span>
                  <%= for level <- 1..5 do %>
                    <label class="cursor-pointer flex items-center gap-1 px-2 py-1 rounded border border-base-300 hover:border-primary/60">
                      <input
                        type="radio"
                        name={row.form[:difficulty].name}
                        value={level}
                        checked={row.form[:difficulty].value in [level, to_string(level)]}
                        class="radio radio-xs radio-primary"
                      />
                      <span class="text-xs">{level}</span>
                    </label>
                  <% end %>
                  <span class="text-xs text-neutral-content/50 ml-1">
                    1 too easy · 3 just right · 5 too hard
                  </span>
                  <div class="flex-1"></div>
                  <button type="submit" class="btn btn-sm btn-primary">
                    <.icon name="hero-check-micro" class="size-4" /> Save
                  </button>
                </div>
              </.form>
            </div>
          </li>
        <% end %>
      </ul>
    </Layouts.app>
    """
  end
end
