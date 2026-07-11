defmodule ElectricbrainWeb.MealLive.Shopping do
  @moduledoc """
  Checkable shopping list for a confirmed meal week. Defaults to the
  same week `/meals` shows (next week from Saturday onward); falls
  back to the current week's list when the default week isn't
  confirmed yet.
  """

  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Meals.Planning
  alias Electricbrain.Meals.ShoppingListItem

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Shopping list")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    user = socket.assigns.current_user

    week_start =
      case params["week"] do
        nil -> Planning.default_week_start(user)
        str -> Date.from_iso8601!(str)
      end

    {:noreply, socket |> assign(:requested_week, week_start) |> load_list()}
  end

  defp load_list(socket) do
    user = socket.assigns.current_user
    requested = socket.assigns.requested_week

    meal_week =
      [requested, Date.add(requested, -7)]
      |> Enum.map(&Planning.week_for(user, &1))
      |> Enum.find(&(&1 && &1.status == :confirmed))

    socket
    |> assign(:meal_week, meal_week)
    |> assign(:items, if(meal_week, do: Planning.shopping_list(user, meal_week), else: []))
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    ShoppingListItem
    |> Ash.get!(id, actor: user)
    |> Ash.Changeset.for_update(:toggle_checked, %{}, actor: user)
    |> Ash.update!()

    {:noreply, load_list(socket)}
  end

  defp checked_count(items), do: Enum.count(items, & &1.checked_at)

  defp quantity_str(decimal) do
    grams = Decimal.to_float(decimal)

    if grams >= 1000 do
      "#{Float.round(grams / 1000, 2)} kg"
    else
      "#{round(grams)} g"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-accent">
            Shopping list
          </h1>
          <p :if={@meal_week} class="text-sm text-neutral-content/70">
            Week of {Calendar.strftime(@meal_week.week_start, "%d %b %Y")} · {checked_count(@items)}/{length(
              @items
            )} in the trolley
          </p>
        </div>
        <.link navigate={~p"/meals"} class="btn btn-ghost btn-sm">
          <.icon name="hero-calendar-days-micro" class="size-4" /> Meal plan
        </.link>
      </div>

      <%= if @meal_week == nil do %>
        <div class="card bg-base-200 border border-base-300">
          <div class="card-body items-center text-center">
            <p class="text-neutral-content/70">
              No confirmed meal plan yet — the shopping list appears once a week is confirmed.
            </p>
            <.link navigate={~p"/meals"} class="btn btn-primary btn-sm">Go to meal plan</.link>
          </div>
        </div>
      <% else %>
        <div class="card bg-base-200 border border-base-300">
          <div class="card-body p-4">
            <ul class="divide-y divide-base-300/60">
              <li :for={item <- @items} class="flex items-center gap-3 py-2">
                <input
                  type="checkbox"
                  checked={item.checked_at != nil}
                  phx-click="toggle"
                  phx-value-id={item.id}
                  class="checkbox checkbox-sm checkbox-primary"
                />
                <span class={[
                  "flex-1 min-w-0",
                  item.checked_at && "line-through text-neutral-content/40"
                ]}>
                  {item.ingredient.name}
                </span>
                <span class="text-sm font-medium tabular-nums">
                  {quantity_str(item.total_quantity_g)}
                </span>
              </li>
            </ul>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
