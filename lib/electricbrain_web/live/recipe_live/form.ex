defmodule ElectricbrainWeb.RecipeLive.Form do
  @moduledoc """
  New/edit recipe form. Ingredient rows are managed in LiveView state
  (each row: picked ingredient + grams + a search box while unpicked)
  and handed to the Recipe action as the `recipe_ingredients` argument
  on save — `manage_relationship(:direct_control)` diffs them against
  the existing rows by the `[recipe_id, ingredient_id]` identity.
  """

  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Meals.Ingredient
  alias Electricbrain.Meals.Macros
  alias Electricbrain.Meals.Recipe

  @result_limit 8

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    user = socket.assigns.current_user

    socket
    |> assign(:page_title, "New recipe")
    |> assign(:recipe, nil)
    |> assign(:form, new_form(user))
    |> assign(:rows, [empty_row()])
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = socket.assigns.current_user

    recipe =
      Recipe
      |> Ash.Query.filter(id == ^id)
      |> Ash.Query.load(recipe_ingredients: [:ingredient])
      |> Ash.read_one!(actor: user)

    rows =
      case recipe.recipe_ingredients do
        [] ->
          [empty_row()]

        recipe_ingredients ->
          Enum.map(recipe_ingredients, fn ri ->
            %{empty_row() | ingredient: ri.ingredient, quantity_g: decimal_string(ri.quantity_g)}
          end)
      end

    socket
    |> assign(:page_title, "Edit recipe")
    |> assign(:recipe, recipe)
    |> assign(:form, edit_form(user, recipe))
    |> assign(:rows, rows)
  end

  defp new_form(user) do
    Recipe
    |> AshPhoenix.Form.for_create(:create, actor: user)
    |> to_form()
  end

  defp edit_form(user, recipe) do
    recipe
    |> AshPhoenix.Form.for_update(:update, actor: user)
    |> to_form()
  end

  defp empty_row do
    %{
      key: "row-#{System.unique_integer([:positive])}",
      ingredient: nil,
      quantity_g: "",
      search: "",
      results: []
    }
  end

  defp decimal_string(decimal),
    do: decimal |> Decimal.normalize() |> Decimal.to_string(:normal)

  @impl true
  def handle_event("validate", %{"form" => form_params} = params, socket) do
    rows = update_rows(socket.assigns.rows, params["rows"] || %{})

    rows =
      case params["_target"] do
        ["rows", key, "search"] -> search_row(rows, key, socket.assigns.current_user)
        _ -> rows
      end

    {:noreply,
     socket
     |> assign(:form, AshPhoenix.Form.validate(socket.assigns.form, form_params))
     |> assign(:rows, rows)}
  end

  def handle_event("add_row", _params, socket) do
    {:noreply, assign(socket, :rows, socket.assigns.rows ++ [empty_row()])}
  end

  def handle_event("remove_row", %{"key" => key}, socket) do
    rows =
      case Enum.reject(socket.assigns.rows, &(&1.key == key)) do
        [] -> [empty_row()]
        rows -> rows
      end

    {:noreply, assign(socket, :rows, rows)}
  end

  def handle_event("pick_ingredient", %{"key" => key, "id" => id}, socket) do
    user = socket.assigns.current_user
    ingredient = Ash.get!(Ingredient, id, actor: user)

    rows =
      Enum.map(socket.assigns.rows, fn
        %{key: ^key} = row -> %{row | ingredient: ingredient, search: "", results: []}
        row -> row
      end)

    {:noreply, assign(socket, :rows, rows)}
  end

  def handle_event("clear_ingredient", %{"key" => key}, socket) do
    rows =
      Enum.map(socket.assigns.rows, fn
        %{key: ^key} = row -> %{row | ingredient: nil, search: "", results: []}
        row -> row
      end)

    {:noreply, assign(socket, :rows, rows)}
  end

  def handle_event("save", %{"form" => form_params}, socket) do
    ingredient_params =
      socket.assigns.rows
      |> Enum.filter(& &1.ingredient)
      |> Enum.map(&%{"ingredient_id" => &1.ingredient.id, "quantity_g" => &1.quantity_g})

    params = Map.put(form_params, "recipe_ingredients", ingredient_params)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _recipe} ->
        {:noreply, push_navigate(socket, to: ~p"/recipes")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  defp update_rows(rows, row_params) do
    Enum.map(rows, fn row ->
      case row_params[row.key] do
        nil ->
          row

        fields ->
          %{
            row
            | quantity_g: Map.get(fields, "quantity_g", row.quantity_g),
              search: Map.get(fields, "search", row.search)
          }
      end
    end)
  end

  defp search_row(rows, key, user) do
    Enum.map(rows, fn
      %{key: ^key} = row -> %{row | results: search_ingredients(user, String.trim(row.search))}
      row -> row
    end)
  end

  defp search_ingredients(_user, ""), do: []

  defp search_ingredients(user, query) do
    Ingredient
    |> Ash.Query.for_read(:search, %{q: query}, actor: user)
    |> Ash.Query.sort(name: :asc)
    |> Ash.Query.limit(@result_limit)
    |> Ash.read!()
  end

  # Live preview: per-serving macros from the current rows and the
  # servings field — same math the generator will use.
  defp preview(rows, form) do
    servings =
      case Float.parse(to_string(form[:servings].value || "1")) do
        {f, _} when f > 0 -> f
        _ -> 1.0
      end

    rows
    |> Enum.filter(& &1.ingredient)
    |> Enum.flat_map(fn row ->
      case Float.parse(to_string(row.quantity_g)) do
        {grams, _} when grams > 0 -> [Macros.for_quantity(row.ingredient, grams)]
        _ -> []
      end
    end)
    |> Macros.sum()
    |> Macros.scale(1.0 / servings)
  end

  defp fmt(f), do: :erlang.float_to_binary(Float.round(f * 1.0, 1), [:compact, decimals: 1])

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <h1 class="font-display text-3xl font-bold tracking-tight text-accent">
          {if @recipe, do: "Edit recipe", else: "New recipe"}
        </h1>
        <.link navigate={~p"/recipes"} class="btn btn-ghost btn-sm">Back to recipes</.link>
      </div>

      <.form
        for={@form}
        id="recipe-form"
        phx-change="validate"
        phx-submit="save"
        class="card bg-base-200 border border-base-300"
      >
        <div class="card-body space-y-4">
          <div class="grid sm:grid-cols-3 gap-3">
            <div class="sm:col-span-2">
              <label class="label"><span class="label-text text-xs">Name</span></label>
              <input
                type="text"
                name={@form[:name].name}
                value={Phoenix.HTML.Form.normalize_value("text", @form[:name].value)}
                class="input input-bordered w-full bg-base-100"
                placeholder="Chicken burrito bowls"
                required
                autocomplete="off"
              />
            </div>

            <div>
              <label class="label"><span class="label-text text-xs">Slot</span></label>
              <select name={@form[:slot_type].name} class="select select-bordered bg-base-100 w-full">
                <option
                  value="breakfast"
                  selected={@form[:slot_type].value in [:breakfast, "breakfast"]}
                >
                  Breakfast
                </option>
                <option
                  value="main"
                  selected={@form[:slot_type].value in [nil, "", :main, "main"]}
                >
                  Main (lunch / dinner)
                </option>
                <option value="snack" selected={@form[:slot_type].value in [:snack, "snack"]}>
                  Snack
                </option>
                <option value="shake" selected={@form[:slot_type].value in [:shake, "shake"]}>
                  Shake
                </option>
              </select>
            </div>

            <div>
              <label class="label">
                <span class="label-text text-xs">Servings this makes</span>
              </label>
              <input
                type="number"
                step="any"
                min="0.25"
                name={@form[:servings].name}
                value={Phoenix.HTML.Form.normalize_value("number", @form[:servings].value) || 1}
                class="input input-bordered w-full bg-base-100"
                required
                autocomplete="off"
              />
            </div>

            <div class="sm:col-span-3">
              <label class="label">
                <span class="label-text text-xs">Instructions (optional)</span>
              </label>
              <textarea
                name={@form[:instructions].name}
                class="textarea textarea-bordered w-full bg-base-100"
                rows="3"
                placeholder="Prep steps, oven temps, portioning notes…"
              >{Phoenix.HTML.Form.normalize_value("textarea", @form[:instructions].value)}</textarea>
            </div>
          </div>

          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <h2 class="font-medium text-sm">Ingredients</h2>
              <button type="button" phx-click="add_row" class="btn btn-ghost btn-xs">
                <.icon name="hero-plus-micro" class="size-4" /> Add ingredient
              </button>
            </div>

            <%= for row <- @rows do %>
              <div class="flex items-start gap-2">
                <div class="flex-1 min-w-0">
                  <%= if row.ingredient do %>
                    <div class="flex items-center gap-2 py-2">
                      <span class="font-medium text-sm truncate">{row.ingredient.name}</span>
                      <button
                        type="button"
                        phx-click="clear_ingredient"
                        phx-value-key={row.key}
                        class="btn btn-ghost btn-xs"
                      >
                        change
                      </button>
                    </div>
                  <% else %>
                    <input
                      type="text"
                      name={"rows[#{row.key}][search]"}
                      value={row.search}
                      phx-debounce="300"
                      placeholder="Search ingredients…"
                      class="input input-bordered input-sm w-full bg-base-100"
                      autocomplete="off"
                    />
                    <%= if row.results != [] do %>
                      <ul class="menu bg-base-100 border border-base-300 rounded-box mt-1 p-1 shadow">
                        <%= for result <- row.results do %>
                          <li>
                            <button
                              type="button"
                              phx-click="pick_ingredient"
                              phx-value-key={row.key}
                              phx-value-id={result.id}
                              class="text-left text-sm"
                            >
                              {result.name}
                              <span class="text-xs opacity-60">
                                {result.kcal_per_100g
                                |> Decimal.round(0)
                                |> Decimal.to_string(:normal)} kcal/100g
                              </span>
                            </button>
                          </li>
                        <% end %>
                      </ul>
                    <% end %>
                  <% end %>
                </div>

                <input
                  type="number"
                  step="any"
                  min="0"
                  name={"rows[#{row.key}][quantity_g]"}
                  value={row.quantity_g}
                  placeholder="grams"
                  class="input input-bordered input-sm w-28 bg-base-100"
                  autocomplete="off"
                />

                <button
                  type="button"
                  phx-click="remove_row"
                  phx-value-key={row.key}
                  class="btn btn-ghost btn-xs text-error mt-1"
                  title="Remove"
                >
                  <.icon name="hero-x-mark-micro" class="size-4" />
                </button>
              </div>
            <% end %>
          </div>

          <% macros = preview(@rows, @form) %>
          <div class="bg-base-100 border border-base-300 rounded-box p-3 text-sm" id="macro-preview">
            <span class="font-medium">Per serving:</span>
            {round(macros.kcal)} kcal · P {fmt(macros.protein_g)}g · F {fmt(macros.fat_g)}g
            · C {fmt(macros.carbs_g)}g · fibre {fmt(macros.fibre_g)}g
          </div>

          <div class="flex justify-end gap-2">
            <.link navigate={~p"/recipes"} class="btn btn-ghost">Cancel</.link>
            <button type="submit" class="btn btn-primary">
              {if @recipe, do: "Save", else: "Create"}
            </button>
          </div>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
