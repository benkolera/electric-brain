defmodule ElectricbrainWeb.RecipeLive.Index do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Meals.Macros
  alias Electricbrain.Meals.Recipe

  @slot_order [:breakfast, :main, :snack, :shake]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Recipes")
     |> assign(:recipes, list_recipes(user))}
  end

  defp list_recipes(user) do
    Recipe
    |> Ash.Query.sort(name: :asc)
    |> Ash.Query.load(recipe_ingredients: [:ingredient])
    |> Ash.read!(actor: user)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Recipe
         |> Ash.get!(id, actor: user)
         |> Ash.destroy(actor: user) do
      :ok ->
        {:noreply, assign(socket, :recipes, list_recipes(user))}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Could not delete that recipe — it may be in a meal plan")}
    end
  end

  defp grouped(recipes) do
    groups = Enum.group_by(recipes, & &1.slot_type)

    @slot_order
    |> Enum.map(&{&1, Map.get(groups, &1, [])})
    |> Enum.reject(fn {_, items} -> items == [] end)
  end

  defp slot_label(:breakfast), do: "Breakfasts"
  defp slot_label(:main), do: "Mains"
  defp slot_label(:snack), do: "Snacks"
  defp slot_label(:shake), do: "Shakes"

  defp fmt(f), do: :erlang.float_to_binary(Float.round(f * 1.0, 1), [:compact, decimals: 1])
  defp fmt_kcal(f), do: round(f)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-accent">
            Recipes
          </h1>
          <p class="text-sm text-neutral-content/70">
            Dishes built from your ingredient library — macros per serving calculated for you.
          </p>
        </div>
        <.link navigate={~p"/recipes/new"} class="btn btn-primary btn-sm">
          <.icon name="hero-plus-micro" class="size-4" /> Add recipe
        </.link>
      </div>

      <%= if @recipes == [] do %>
        <div class="text-center py-12 text-neutral-content/60">
          No recipes yet. The weekly meal plan needs a couple of breakfasts, a couple of mains,
          a snack, and a shake to work with.
        </div>
      <% else %>
        <%= for {slot, items} <- grouped(@recipes) do %>
          <div class="card bg-base-200 border border-base-300">
            <div class="card-body p-4">
              <h2 class="card-title text-base">{slot_label(slot)}</h2>
              <ul class="divide-y divide-base-300/60">
                <%= for recipe <- items do %>
                  <% macros = Macros.per_serving(recipe) %>
                  <li class="flex items-center gap-3 py-2">
                    <div class="flex-1 min-w-0">
                      <.link
                        navigate={~p"/recipes/#{recipe.id}/edit"}
                        class="font-medium hover:underline"
                      >
                        {recipe.name}
                      </.link>
                      <p class="text-xs text-neutral-content/60">
                        {fmt_kcal(macros.kcal)} kcal · P {fmt(macros.protein_g)}g
                        · F {fmt(macros.fat_g)}g · C {fmt(macros.carbs_g)}g
                        <span class="opacity-60">per serving</span>
                        · makes {recipe.servings |> Decimal.normalize() |> Decimal.to_string(:normal)}
                      </p>
                    </div>
                    <button
                      phx-click="delete"
                      phx-value-id={recipe.id}
                      data-confirm={"Delete recipe \"#{recipe.name}\"?"}
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
