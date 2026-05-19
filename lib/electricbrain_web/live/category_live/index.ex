defmodule ElectricbrainWeb.CategoryLive.Index do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Categories.Category

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Categories")
     |> assign(:editing, nil)
     |> assign_categories(user)}
  end

  @impl true
  def handle_event("start_add_root", _params, socket) do
    {:noreply, assign(socket, :editing, {:add, nil})}
  end

  def handle_event("start_add_child", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing, {:add, id})}
  end

  def handle_event("start_rename", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing, {:rename, id})}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  def handle_event("save_new", %{"name" => name, "parent_id" => parent_id}, socket) do
    user = socket.assigns.current_user
    parent_id = if parent_id == "", do: nil, else: parent_id

    case Category
         |> Ash.Changeset.for_create(:create, %{name: name, parent_id: parent_id}, actor: user)
         |> Ash.create() do
      {:ok, _category} ->
        {:noreply,
         socket
         |> assign(:editing, nil)
         |> assign_categories(user)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create category")}
    end
  end

  def handle_event("save_rename", %{"category_id" => id, "name" => name}, socket) do
    user = socket.assigns.current_user

    case Category
         |> Ash.get!(id, actor: user)
         |> Ash.Changeset.for_update(:update, %{name: name}, actor: user)
         |> Ash.update() do
      {:ok, _category} ->
        {:noreply,
         socket
         |> assign(:editing, nil)
         |> assign_categories(user)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not rename category")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Category
         |> Ash.get!(id, actor: user)
         |> Ash.destroy(actor: user) do
      :ok ->
        {:noreply, assign_categories(socket, user)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Can't delete a category that still has children")}
    end
  end

  defp assign_categories(socket, user) do
    categories =
      Category
      |> Ash.Query.sort(inserted_at: :asc)
      |> Ash.read!(actor: user)

    children_by_parent = Enum.group_by(categories, & &1.parent_id)
    roots = Map.get(children_by_parent, nil, [])

    neglect = Electricbrain.Neglect.scores_for_user(user)
    max_neglect = neglect |> Map.values() |> Enum.max(fn -> 0 end)

    socket
    |> assign(:roots, roots)
    |> assign(:children_by_parent, children_by_parent)
    |> assign(:neglect, neglect)
    |> assign(:max_neglect, max_neglect)
  end

  defp neglect_pct(neglect, max, id) do
    score = Map.get(neglect, id, 0)
    if max > 0, do: score / max, else: 0.0
  end

  defp neglect_class(pct) do
    cond do
      pct == 0.0 -> "bg-base-300/30"
      pct < 0.3 -> "bg-success/70"
      pct < 0.7 -> "bg-warning/80"
      true -> "bg-error"
    end
  end

  defp neglect_label(pct) do
    cond do
      pct == 0.0 -> "none"
      pct < 0.3 -> "low"
      pct < 0.7 -> "medium"
      true -> "high"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex items-center justify-between">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-accent drop-shadow-[0_0_12px_var(--color-accent)]">
            Categories
          </h1>
          <p class="text-sm text-neutral-content/70">
            The backbone — break life into areas you want to keep alive.
          </p>
        </div>
        <button
          type="button"
          phx-click="start_add_root"
          class="btn btn-primary btn-sm"
        >
          <.icon name="hero-plus-micro" class="size-4" /> Add root
        </button>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body p-4">
          <%= if @editing == {:add, nil} do %>
            <.add_form parent_id={nil} nested={false} />
          <% end %>

          <ul class="space-y-0.5">
            <%= for node <- @roots do %>
              <.tree_node
                node={node}
                children_by_parent={@children_by_parent}
                editing={@editing}
                neglect={@neglect}
                max_neglect={@max_neglect}
              />
            <% end %>
          </ul>

          <%= if @roots == [] and @editing != {:add, nil} do %>
            <p class="text-center py-8 text-neutral-content/60">
              No categories yet. Start with the broad areas of your life.
            </p>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :node, :map, required: true
  attr :children_by_parent, :map, required: true
  attr :editing, :any, required: true
  attr :neglect, :map, required: true
  attr :max_neglect, :float, required: true

  defp tree_node(assigns) do
    pct = neglect_pct(assigns.neglect, assigns.max_neglect, assigns.node.id)

    assigns =
      assigns
      |> assign(:children, Map.get(assigns.children_by_parent, assigns.node.id, []))
      |> assign(:neglect_pct, pct)
      |> assign(:neglect_bar_class, neglect_class(pct))

    ~H"""
    <li>
      <div class="flex items-center gap-2 py-1.5 px-2 rounded hover:bg-base-300/40">
        <%= if @editing == {:rename, @node.id} do %>
          <form
            phx-submit="save_rename"
            class="flex-1 flex items-center gap-2"
          >
            <input type="hidden" name="category_id" value={@node.id} />
            <input
              type="text"
              name="name"
              value={@node.name}
              class="input input-sm input-bordered flex-1 bg-base-100"
              autocomplete="off"
              phx-mounted={JS.focus()}
              phx-window-keydown="cancel"
              phx-key="escape"
              required
            />
            <button type="submit" class="btn btn-xs btn-primary">Save</button>
            <button type="button" phx-click="cancel" class="btn btn-xs btn-ghost">Cancel</button>
          </form>
        <% else %>
          <button
            type="button"
            phx-click="start_rename"
            phx-value-id={@node.id}
            class="flex-1 text-left font-medium hover:text-primary truncate"
          >
            {@node.name}
            <%= if @children != [] do %>
              <span class="ml-2 text-xs text-neutral-content/50">({length(@children)})</span>
            <% end %>
          </button>

          <div
            class="w-12 h-1.5 rounded-full bg-base-300/30 overflow-hidden"
            title={"Neglect signal: " <> neglect_label(@neglect_pct)}
          >
            <div
              class={["h-full rounded-full transition-all", @neglect_bar_class]}
              style={"width: #{max(round(@neglect_pct * 100), if(@neglect_pct > 0, do: 6, else: 0))}%"}
            >
            </div>
          </div>

          <div class="flex items-center gap-1">
            <button
              type="button"
              phx-click="start_add_child"
              phx-value-id={@node.id}
              class="btn btn-xs btn-ghost text-neutral-content/60 hover:text-primary"
              title="Add child"
            >
              <.icon name="hero-plus-micro" class="size-3.5" />
            </button>
            <button
              type="button"
              phx-click="delete"
              phx-value-id={@node.id}
              data-confirm={"Delete \"#{@node.name}\"?"}
              class="btn btn-xs btn-ghost text-neutral-content/60 hover:text-error"
              title="Delete"
            >
              <.icon name="hero-x-mark-micro" class="size-3.5" />
            </button>
          </div>
        <% end %>
      </div>

      <%= if @editing == {:add, @node.id} do %>
        <.add_form parent_id={@node.id} nested={true} />
      <% end %>

      <%= if @children != [] do %>
        <ul class="ml-3 pl-3 border-l border-base-300 space-y-0.5">
          <%= for child <- @children do %>
            <.tree_node
              node={child}
              children_by_parent={@children_by_parent}
              editing={@editing}
              neglect={@neglect}
              max_neglect={@max_neglect}
            />
          <% end %>
        </ul>
      <% end %>
    </li>
    """
  end

  attr :parent_id, :any, default: nil
  attr :nested, :boolean, default: false

  defp add_form(assigns) do
    ~H"""
    <form
      phx-submit="save_new"
      class={[
        "flex items-center gap-2 py-1.5 px-2",
        @nested && "ml-3 pl-3 border-l border-base-300"
      ]}
    >
      <input type="hidden" name="parent_id" value={@parent_id} />
      <input
        type="text"
        name="name"
        placeholder="Category name"
        class="input input-sm input-bordered flex-1 bg-base-100"
        autocomplete="off"
        phx-mounted={JS.focus()}
        phx-window-keydown="cancel"
        phx-key="escape"
        required
      />
      <button type="submit" class="btn btn-xs btn-primary">Add</button>
      <button type="button" phx-click="cancel" class="btn btn-xs btn-ghost">Cancel</button>
    </form>
    """
  end
end
