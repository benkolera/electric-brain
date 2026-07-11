defmodule ElectricbrainWeb.IngredientLive.Index do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Meals.Ingredient

  @search_limit 50

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Ingredients")
     |> assign(:query, "")
     |> assign(:create_open, false)
     |> assign(:editing_id, nil)
     |> assign(:form, new_form(user))
     |> assign(:ingredients, list_ingredients(user, ""))}
  end

  defp new_form(user) do
    Ingredient
    |> AshPhoenix.Form.for_create(:create, actor: user)
    |> to_form()
  end

  defp edit_form(user, ingredient) do
    ingredient
    |> AshPhoenix.Form.for_update(:update, actor: user)
    |> to_form()
  end

  # Blank query: just the user's own entries — the seeded library is 1,588
  # rows, so it's search-only rather than browsable.
  defp list_ingredients(user, "") do
    Ingredient
    |> Ash.Query.filter(not is_nil(user_id))
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(actor: user)
  end

  defp list_ingredients(user, query) do
    Ingredient
    |> Ash.Query.for_read(:search, %{q: query}, actor: user)
    |> Ash.Query.sort(name: :asc)
    |> Ash.Query.limit(@search_limit)
    |> Ash.read!()
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(:query, q)
     |> assign(:ingredients, list_ingredients(user, String.trim(q)))}
  end

  def handle_event("toggle_create", _params, socket) do
    user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(:create_open, !socket.assigns.create_open)
     |> assign(:editing_id, nil)
     |> assign(:form, new_form(user))}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    ingredient = Ash.get!(Ingredient, id, actor: user)

    {:noreply,
     socket
     |> assign(:create_open, false)
     |> assign(:editing_id, id)
     |> assign(:form, edit_form(user, ingredient))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket |> assign(:editing_id, nil) |> assign(:form, new_form(socket.assigns.current_user))}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    user = socket.assigns.current_user

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _ingredient} ->
        {:noreply,
         socket
         |> assign(:create_open, false)
         |> assign(:editing_id, nil)
         |> assign(:form, new_form(user))
         |> assign(:ingredients, list_ingredients(user, String.trim(socket.assigns.query)))}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Ingredient
         |> Ash.get!(id, actor: user)
         |> Ash.destroy(actor: user) do
      :ok ->
        {:noreply,
         assign(socket, :ingredients, list_ingredients(user, String.trim(socket.assigns.query)))}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not delete that ingredient — it may be used by a recipe"
         )}
    end
  end

  defp own?(ingredient, user), do: ingredient.user_id == user.id

  defp fmt(decimal),
    do: decimal |> Decimal.round(1) |> Decimal.normalize() |> Decimal.to_string(:normal)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-accent">
            Ingredients
          </h1>
          <p class="text-sm text-neutral-content/70">
            Per-100g macros powering recipe math. Search the AFCD library or add your own from the packet label.
          </p>
        </div>
        <button type="button" phx-click="toggle_create" class="btn btn-primary btn-sm">
          <.icon name="hero-plus-micro" class="size-4" /> Add ingredient
        </button>
      </div>

      <form phx-change="search" phx-submit="search" class="w-full" onsubmit="return false;">
        <input
          type="search"
          name="q"
          value={@query}
          phx-debounce="300"
          placeholder="Search ingredients — chicken breast, rolled oats, broccoli…"
          class="input input-bordered w-full bg-base-100"
          autocomplete="off"
        />
      </form>

      <%= if @create_open or @editing_id do %>
        <.ingredient_form form={@form} editing={@editing_id != nil} />
      <% end %>

      <%= if @ingredients == [] do %>
        <div class="text-center py-12 text-neutral-content/60">
          <%= if @query == "" do %>
            No custom ingredients yet. Search the library above, or add one from a packet label.
          <% else %>
            Nothing matches "{@query}". Add it as a custom ingredient?
          <% end %>
        </div>
      <% else %>
        <div class="card bg-base-200 border border-base-300">
          <div class="card-body p-4">
            <ul class="divide-y divide-base-300/60">
              <%= for ingredient <- @ingredients do %>
                <li class="flex items-center gap-3 py-2">
                  <div class="flex-1 min-w-0">
                    <span class="font-medium">{ingredient.name}</span>
                    <p class="text-xs text-neutral-content/60">
                      {fmt(ingredient.kcal_per_100g)} kcal · P {fmt(ingredient.protein_g_per_100g)}g
                      · F {fmt(ingredient.fat_g_per_100g)}g · C {fmt(ingredient.carbs_g_per_100g)}g
                      · fibre {fmt(ingredient.fibre_g_per_100g)}g
                      <span class="opacity-60">per 100g</span>
                    </p>
                  </div>
                  <%= if ingredient.source == :afcd do %>
                    <span class="badge badge-ghost badge-sm">AFCD</span>
                  <% else %>
                    <span class="badge badge-primary badge-sm">Custom</span>
                  <% end %>
                  <%= if own?(ingredient, @current_user) do %>
                    <button
                      phx-click="edit"
                      phx-value-id={ingredient.id}
                      class="btn btn-xs btn-ghost"
                      title="Edit"
                    >
                      <.icon name="hero-pencil-micro" class="size-4" />
                    </button>
                    <button
                      phx-click="delete"
                      phx-value-id={ingredient.id}
                      data-confirm={"Delete ingredient \"#{ingredient.name}\"?"}
                      class="btn btn-xs btn-ghost text-error"
                      title="Delete"
                    >
                      <.icon name="hero-x-mark-micro" class="size-4" />
                    </button>
                  <% end %>
                </li>
              <% end %>
            </ul>
            <%= if @query != "" and length(@ingredients) >= 50 do %>
              <p class="text-xs text-neutral-content/50">
                Showing the first 50 matches — keep typing to narrow down.
              </p>
            <% end %>
          </div>
        </div>
      <% end %>

      <p class="text-xs text-neutral-content/40">
        Ingredient library derived from the
        <a
          href="https://www.foodstandards.gov.au/science-data/food-nutrient-databases/afcd"
          target="_blank"
          rel="noopener"
          class="underline"
        >
          Australian Food Composition Database
        </a>
        © Food Standards Australia New Zealand, licensed under CC-BY 4.0.
      </p>
    </Layouts.app>
    """
  end

  attr :form, :map, required: true
  attr :editing, :boolean, required: true

  defp ingredient_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="ingredient-form"
      phx-change="validate"
      phx-submit="save"
      class="card bg-base-200 border border-base-300"
    >
      <div class="card-body space-y-3">
        <h2 class="card-title text-base">
          {if @editing, do: "Edit ingredient", else: "New ingredient"}
        </h2>
        <div class="grid sm:grid-cols-3 gap-3">
          <div class="sm:col-span-3">
            <label class="label"><span class="label-text text-xs">Name</span></label>
            <input
              type="text"
              name={@form[:name].name}
              value={Phoenix.HTML.Form.normalize_value("text", @form[:name].value)}
              class="input input-bordered w-full bg-base-100"
              placeholder="Chobani plain Greek yogurt"
              required
              autocomplete="off"
            />
          </div>

          <.macro_input form={@form} field={:kcal_per_100g} label="kcal / 100g" />
          <.macro_input form={@form} field={:protein_g_per_100g} label="Protein g / 100g" />
          <.macro_input form={@form} field={:fat_g_per_100g} label="Fat g / 100g" />
          <.macro_input form={@form} field={:carbs_g_per_100g} label="Carbs g / 100g" />
          <.macro_input form={@form} field={:fibre_g_per_100g} label="Fibre g / 100g" />
        </div>

        <div class="flex justify-end gap-2">
          <button
            type="button"
            phx-click={if @editing, do: "cancel_edit", else: "toggle_create"}
            class="btn btn-ghost"
          >
            Cancel
          </button>
          <button type="submit" class="btn btn-primary">
            {if @editing, do: "Save", else: "Create"}
          </button>
        </div>
      </div>
    </.form>
    """
  end

  attr :form, :map, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true

  defp macro_input(assigns) do
    ~H"""
    <div>
      <label class="label"><span class="label-text text-xs">{@label}</span></label>
      <input
        type="number"
        step="any"
        min="0"
        name={@form[@field].name}
        value={Phoenix.HTML.Form.normalize_value("number", @form[@field].value)}
        class="input input-bordered w-full bg-base-100"
        required={@field != :fibre_g_per_100g}
        autocomplete="off"
      />
    </div>
    """
  end
end
