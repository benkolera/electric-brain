defmodule ElectricbrainWeb.CategoryPicker do
  @moduledoc """
  Typeahead category picker. State lives in the parent LiveView; this module
  contributes a function component for rendering and a `handle_event` hook
  that catches the picker's events.

  Usage:

      def mount(_params, _session, socket) do
        {:ok,
         socket
         |> CategoryPicker.assign(user)
         |> CategoryPicker.attach()}
      end

      # ...in render
      <CategoryPicker.picker
        categories={@categories}
        categories_by_id={@categories_by_id}
        selected_id={@picker_selected_id}
        query={@picker_query}
        open={@picker_open}
      />
  """
  use Phoenix.Component
  use ElectricbrainWeb, :verified_routes

  alias Electricbrain.Categories
  alias Phoenix.LiveView

  @doc """
  Initialises the assigns used by the picker. Defaults the selected category to
  the user's Inbox.
  """
  def assign(socket, user) do
    categories = Categories.list_with_paths(user)
    inbox_id = Enum.find_value(categories, &(&1.kind == :inbox && &1.id))

    socket
    |> Phoenix.Component.assign(:categories, categories)
    |> Phoenix.Component.assign(:categories_by_id, Map.new(categories, &{&1.id, &1}))
    |> Phoenix.Component.assign(:inbox_id, inbox_id)
    |> Phoenix.Component.assign(:picker_query, "")
    |> Phoenix.Component.assign(:picker_open, false)
    |> Phoenix.Component.assign(:picker_selected_id, inbox_id)
  end

  @doc "Resets the picker to the inbox (used after the parent successfully submits)."
  def reset(socket) do
    socket
    |> Phoenix.Component.assign(:picker_selected_id, socket.assigns.inbox_id)
    |> Phoenix.Component.assign(:picker_query, "")
    |> Phoenix.Component.assign(:picker_open, false)
  end

  @doc """
  Attaches a `handle_event` hook that catches the picker's events. Parent's own
  `handle_event/3` does not need to know about picker events at all.
  """
  def attach(socket) do
    LiveView.attach_hook(socket, :category_picker, :handle_event, &handle_picker_event/3)
  end

  defp handle_picker_event("open_picker", _params, socket) do
    {:halt,
     socket
     |> Phoenix.Component.assign(:picker_open, true)
     |> Phoenix.Component.assign(:picker_query, "")}
  end

  defp handle_picker_event("close_picker", _params, socket) do
    {:halt,
     socket
     |> Phoenix.Component.assign(:picker_open, false)
     |> Phoenix.Component.assign(:picker_query, "")}
  end

  defp handle_picker_event("filter_categories", %{"value" => query}, socket) do
    {:halt,
     socket
     |> Phoenix.Component.assign(:picker_query, query)
     |> Phoenix.Component.assign(:picker_open, true)}
  end

  defp handle_picker_event("select_category", %{"id" => id}, socket) do
    {:halt,
     socket
     |> Phoenix.Component.assign(:picker_selected_id, id)
     |> Phoenix.Component.assign(:picker_open, false)
     |> Phoenix.Component.assign(:picker_query, "")}
  end

  defp handle_picker_event(_event, _params, socket), do: {:cont, socket}

  @doc """
  Joins a path list into a "Health › Exercise" breadcrumb string.
  """
  def breadcrumb(path) when is_list(path), do: Enum.join(path, " › ")
  def breadcrumb(_), do: ""

  attr :categories, :list, required: true
  attr :categories_by_id, :map, required: true
  attr :selected_id, :any, required: true
  attr :query, :string, required: true
  attr :open, :boolean, required: true

  def picker(assigns) do
    ~H"""
    <div class="relative" phx-click-away="close_picker">
      <input
        type="text"
        value={input_value(@categories_by_id, @selected_id, @query, @open)}
        phx-keyup="filter_categories"
        phx-debounce="60"
        phx-focus="open_picker"
        phx-window-keydown="close_picker"
        phx-key="escape"
        class="input input-bordered w-full bg-base-100"
        placeholder="Search category…"
        autocomplete="off"
      />
      <%= if @open do %>
        <ul class="absolute z-20 mt-1 w-full max-h-60 overflow-auto bg-base-100 border border-base-300 rounded-box shadow-lg">
          <%= for cat <- filter(@categories, @query) do %>
            <li
              phx-click="select_category"
              phx-value-id={cat.id}
              class={[
                "px-3 py-2 cursor-pointer text-sm hover:bg-primary/20",
                cat.id == @selected_id && "bg-primary/10"
              ]}
            >
              {breadcrumb(cat.path)}
              <%= if cat.kind == :inbox do %>
                <span class="ml-2 text-xs text-neutral-content/50">(inbox)</span>
              <% end %>
            </li>
          <% end %>
          <%= if filter(@categories, @query) == [] do %>
            <li class="px-3 py-2 text-sm text-neutral-content/60">No matches</li>
          <% end %>
        </ul>
      <% end %>
    </div>
    """
  end

  defp filter(categories, ""), do: categories

  defp filter(categories, query) do
    needle = String.downcase(query)

    Enum.filter(categories, fn cat ->
      cat.path |> breadcrumb() |> String.downcase() |> String.contains?(needle)
    end)
  end

  defp input_value(_categories_by_id, _selected_id, query, true), do: query

  defp input_value(categories_by_id, selected_id, _query, false) do
    case Map.get(categories_by_id, selected_id) do
      nil -> ""
      cat -> breadcrumb(cat.path)
    end
  end
end
