defmodule ElectricbrainWeb.MealLive.Index do
  @moduledoc """
  The weekly meal plan: a 5×5 grid (Mon–Fri × breakfast/shake/lunch/
  snack/dinner). Draft weeks can be regenerated, swapped per-cell, and
  confirmed; confirmed weeks are read-only. Day totals compare against
  the targets snapshotted on the MealWeek at generation time.
  """

  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Meals
  alias Electricbrain.Meals.Macros
  alias Electricbrain.Meals.PlannedMeal
  alias Electricbrain.Meals.Planning
  alias Electricbrain.Meals.Recipe

  @slots [:breakfast, :shake, :lunch, :snack, :dinner]
  @slot_types %{breakfast: :breakfast, shake: :shake, lunch: :main, snack: :snack, dinner: :main}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Meals")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    user = socket.assigns.current_user

    week_start =
      case params["week"] do
        nil -> Planning.default_week_start(user)
        str -> Date.from_iso8601!(str)
      end

    {:noreply,
     socket
     |> assign(:week_start, week_start)
     |> assign(:editing_cell, nil)
     |> load_week()}
  end

  defp load_week(socket) do
    user = socket.assigns.current_user
    week_start = socket.assigns.week_start

    socket
    |> assign(:profile, Meals.profile_for(user))
    |> assign(:targets, Planning.resolved_targets(user))
    |> assign(:meal_week, Planning.week_for(user, week_start))
    |> assign(:recipes, list_recipes(user))
  end

  defp list_recipes(user) do
    Recipe
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(actor: user)
  end

  @impl true
  def handle_event("generate", _params, socket) do
    user = socket.assigns.current_user

    case Planning.generate_week(user, socket.assigns.week_start) do
      {:ok, _week} ->
        {:noreply, socket |> assign(:editing_cell, nil) |> load_week()}

      {:error, :week_confirmed} ->
        {:noreply, put_flash(socket, :error, "This week is confirmed — it can't be regenerated")}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Set up your nutrition profile before generating a plan")}
    end
  end

  def handle_event("confirm", _params, socket) do
    user = socket.assigns.current_user
    Planning.confirm_week(user, socket.assigns.meal_week)

    {:noreply,
     socket
     |> assign(:editing_cell, nil)
     |> put_flash(:info, "Week confirmed — shopping list is ready")
     |> load_week()}
  end

  def handle_event("edit_cell", %{"date" => date, "slot" => slot}, socket) do
    {:noreply,
     assign(socket, :editing_cell, {Date.from_iso8601!(date), String.to_existing_atom(slot)})}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_cell, nil)}
  end

  def handle_event("swap", %{"recipe_id" => recipe_id, "servings" => servings}, socket) do
    user = socket.assigns.current_user
    {date, slot} = socket.assigns.editing_cell

    case find_meal(socket.assigns.meal_week, date, slot) do
      nil ->
        PlannedMeal
        |> Ash.Changeset.for_create(
          :create,
          %{
            meal_week_id: socket.assigns.meal_week.id,
            recipe_id: recipe_id,
            date: date,
            slot: slot,
            servings: servings
          },
          actor: user
        )
        |> Ash.create!()

      meal ->
        meal
        |> Ash.Changeset.for_update(:swap, %{recipe_id: recipe_id, servings: servings},
          actor: user
        )
        |> Ash.update!()
    end

    {:noreply, socket |> assign(:editing_cell, nil) |> load_week()}
  end

  def handle_event("remove_meal", _params, socket) do
    user = socket.assigns.current_user
    {date, slot} = socket.assigns.editing_cell

    case find_meal(socket.assigns.meal_week, date, slot) do
      nil -> :ok
      meal -> Ash.destroy!(meal, actor: user)
    end

    {:noreply, socket |> assign(:editing_cell, nil) |> load_week()}
  end

  # --- helpers ---------------------------------------------------------

  defp days(week_start), do: Enum.map(0..4, &Date.add(week_start, &1))

  defp find_meal(nil, _date, _slot), do: nil

  defp find_meal(meal_week, date, slot) do
    Enum.find(meal_week.planned_meals, &(&1.date == date and &1.slot == slot))
  end

  defp day_totals(meal_week, date) do
    meal_week.planned_meals
    |> Enum.filter(&(&1.date == date))
    |> Enum.map(fn meal ->
      meal.recipe
      |> Macros.per_serving()
      |> Macros.scale(Decimal.to_float(meal.servings))
    end)
    |> Macros.sum()
  end

  defp on_target?(actual, target), do: abs(actual - target) <= target * 0.1

  defp slot_label(:breakfast), do: "Breakfast"
  defp slot_label(:shake), do: "Shake"
  defp slot_label(:lunch), do: "Lunch"
  defp slot_label(:snack), do: "Snack"
  defp slot_label(:dinner), do: "Dinner"

  defp slot_recipes(recipes, slot), do: Enum.filter(recipes, &(&1.slot_type == @slot_types[slot]))

  defp servings_str(decimal),
    do: decimal |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp slots, do: @slots

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-accent">
            Meals
          </h1>
          <p class="text-sm text-neutral-content/70">
            Week of {Calendar.strftime(@week_start, "%d %b")} — {Calendar.strftime(
              Date.add(@week_start, 4),
              "%d %b %Y"
            )}
          </p>
        </div>
        <div class="flex items-center gap-2">
          <.link
            patch={~p"/meals?week=#{Date.to_iso8601(Date.add(@week_start, -7))}"}
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-chevron-left-micro" class="size-4" /> Prev
          </.link>
          <.link
            patch={~p"/meals?week=#{Date.to_iso8601(Date.add(@week_start, 7))}"}
            class="btn btn-ghost btn-sm"
          >
            Next <.icon name="hero-chevron-right-micro" class="size-4" />
          </.link>
          <.link navigate={~p"/meals/settings"} class="btn btn-ghost btn-sm" title="Meal settings">
            <.icon name="hero-cog-6-tooth-micro" class="size-4" />
          </.link>
        </div>
      </div>

      <%= cond do %>
        <% @profile == nil or match?({:error, _}, @targets) -> %>
          <div class="card bg-base-200 border border-base-300">
            <div class="card-body items-center text-center">
              <p class="text-neutral-content/70">
                The weekly plan needs your calorie and macro targets first.
              </p>
              <.link navigate={~p"/meals/settings"} class="btn btn-primary btn-sm">
                Set up nutrition profile
              </.link>
            </div>
          </div>
        <% @meal_week == nil -> %>
          <div class="card bg-base-200 border border-base-300">
            <div class="card-body items-center text-center">
              <p class="text-neutral-content/70">
                No plan for this week yet — generate one from your recipe library.
              </p>
              <button phx-click="generate" class="btn btn-primary">
                <.icon name="hero-sparkles-micro" class="size-4" /> Generate week
              </button>
              <p class="text-xs text-neutral-content/50">
                2 breakfasts · 2 mains across lunch and dinner · a daily snack · shakes to
                top up protein
              </p>
            </div>
          </div>
        <% true -> %>
          <div class="flex items-center gap-2 flex-wrap">
            <%= if @meal_week.status == :draft do %>
              <span class="badge badge-warning badge-sm">Draft</span>
              <button phx-click="generate" class="btn btn-ghost btn-sm">
                <.icon name="hero-arrow-path-micro" class="size-4" /> Regenerate
              </button>
              <div class="flex-1"></div>
              <button phx-click="confirm" class="btn btn-primary btn-sm">
                <.icon name="hero-check-micro" class="size-4" /> Confirm week
              </button>
            <% else %>
              <span class="badge badge-success badge-sm">Confirmed</span>
              <div class="flex-1"></div>
              <.link
                navigate={~p"/meals/shopping?week=#{Date.to_iso8601(@week_start)}"}
                class="btn btn-ghost btn-sm"
              >
                <.icon name="hero-shopping-cart-micro" class="size-4" /> Shopping list
              </.link>
            <% end %>
          </div>

          <div
            :if={@meal_week.warnings != []}
            class="card bg-warning/10 border border-warning/40"
          >
            <div class="card-body p-4 text-sm space-y-1">
              <p :for={warning <- @meal_week.warnings} class="text-warning-content/90">
                <.icon name="hero-exclamation-triangle-micro" class="size-4 inline" /> {warning}
              </p>
            </div>
          </div>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th class="w-24"></th>
                  <th :for={date <- days(@week_start)} class="text-center">
                    {Calendar.strftime(date, "%a %d")}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={slot <- slots()}>
                  <td class="font-medium text-xs text-neutral-content/70">
                    {slot_label(slot)}
                  </td>
                  <td :for={date <- days(@week_start)} class="text-center align-top">
                    <% meal = find_meal(@meal_week, date, slot) %>
                    <%= if @meal_week.status == :draft do %>
                      <button
                        phx-click="edit_cell"
                        phx-value-date={date}
                        phx-value-slot={slot}
                        class={[
                          "w-full rounded-box border px-2 py-1.5 text-xs hover:border-primary",
                          @editing_cell == {date, slot} && "border-primary",
                          meal == nil && "border-dashed border-base-300 text-neutral-content/40",
                          meal != nil && "border-base-300 bg-base-200"
                        ]}
                      >
                        <%= if meal do %>
                          <span class="font-medium">{meal.recipe.name}</span>
                          <span class="block text-neutral-content/60">
                            ×{servings_str(meal.servings)}
                          </span>
                        <% else %>
                          —
                        <% end %>
                      </button>
                    <% else %>
                      <div class={[
                        "w-full rounded-box px-2 py-1.5 text-xs",
                        meal != nil && "bg-base-200 border border-base-300"
                      ]}>
                        <%= if meal do %>
                          <span class="font-medium">{meal.recipe.name}</span>
                          <span class="block text-neutral-content/60">
                            ×{servings_str(meal.servings)}
                          </span>
                        <% else %>
                          <span class="text-neutral-content/30">—</span>
                        <% end %>
                      </div>
                    <% end %>
                  </td>
                </tr>
                <tr>
                  <td class="font-medium text-xs text-neutral-content/70">vs target</td>
                  <td :for={date <- days(@week_start)} class="text-center">
                    <% totals = day_totals(@meal_week, date) %>
                    <div class="text-xs space-y-0.5">
                      <p class={
                        if on_target?(totals.kcal, @meal_week.target_kcal),
                          do: "text-success",
                          else: "text-warning"
                      }>
                        {round(totals.kcal)} / {@meal_week.target_kcal} kcal
                      </p>
                      <p class={
                        if totals.protein_g >= @meal_week.target_protein_g * 0.95,
                          do: "text-success",
                          else: "text-warning"
                      }>
                        P {round(totals.protein_g)} / {@meal_week.target_protein_g}g
                      </p>
                      <p class="text-neutral-content/60">
                        F {round(totals.fat_g)} / {@meal_week.target_fat_g}g ·
                        C {round(totals.carbs_g)} / {@meal_week.target_carbs_g}g
                      </p>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@editing_cell} class="card bg-base-200 border border-base-300">
            <% {date, slot} = @editing_cell %>
            <% meal = find_meal(@meal_week, date, slot) %>
            <form phx-submit="swap" class="card-body p-4 space-y-3">
              <h2 class="card-title text-base">
                {slot_label(slot)} — {Calendar.strftime(date, "%A %d %b")}
              </h2>
              <div class="flex gap-3 items-end flex-wrap">
                <div class="flex-1 min-w-48">
                  <label class="label"><span class="label-text text-xs">Recipe</span></label>
                  <select name="recipe_id" class="select select-bordered bg-base-100 w-full" required>
                    <option
                      :for={recipe <- slot_recipes(@recipes, slot)}
                      value={recipe.id}
                      selected={meal && meal.recipe_id == recipe.id}
                    >
                      {recipe.name}
                    </option>
                  </select>
                </div>
                <div>
                  <label class="label"><span class="label-text text-xs">Servings</span></label>
                  <input
                    type="number"
                    name="servings"
                    step="0.25"
                    min="0.25"
                    value={(meal && servings_str(meal.servings)) || "1"}
                    class="input input-bordered w-28 bg-base-100"
                    required
                  />
                </div>
                <div class="flex gap-2">
                  <button type="submit" class="btn btn-primary btn-sm">Save</button>
                  <button
                    :if={meal}
                    type="button"
                    phx-click="remove_meal"
                    class="btn btn-ghost btn-sm text-error"
                  >
                    Remove
                  </button>
                  <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">
                    Cancel
                  </button>
                </div>
              </div>
            </form>
          </div>
      <% end %>
    </Layouts.app>
    """
  end
end
