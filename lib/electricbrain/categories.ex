defmodule Electricbrain.Categories do
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.Categories.Category
  end

  @default_categories [
    {"Inbox", :inbox},
    {"Work", :standard},
    {"Health", :standard},
    {"Hobbies", :standard},
    {"Relationships", :standard},
    {"Admin", :standard}
  ]

  @doc """
  Creates the starter set of root categories for a new user. Idempotent —
  skips if the user already has any categories.
  """
  def seed_defaults_for(user) do
    if has_any_category?(user) do
      :ok
    else
      Enum.each(@default_categories, fn {name, kind} ->
        Electricbrain.Categories.Category
        |> Ash.Changeset.for_create(:create, %{name: name, kind: kind}, actor: user)
        |> Ash.create!()
      end)

      :ok
    end
  end

  defp has_any_category?(user) do
    require Ash.Query

    Electricbrain.Categories.Category
    |> Ash.Query.limit(1)
    |> Ash.read!(actor: user)
    |> Enum.any?()
  end

  @doc """
  Returns the user's inbox category, or nil if they don't have one.
  """
  def inbox_for(user) do
    require Ash.Query

    Electricbrain.Categories.Category
    |> Ash.Query.filter(kind == :inbox)
    |> Ash.Query.limit(1)
    |> Ash.read_one(actor: user)
    |> case do
      {:ok, category} -> category
      _ -> nil
    end
  end

  @doc """
  Loads all of a user's categories, decorated with a `:path` field (list of
  ancestor names from root down to this category) and sorted with the inbox
  first, then alphabetically by full path.
  """
  def list_with_paths(user) do
    require Ash.Query

    cats =
      Electricbrain.Categories.Category
      |> Ash.Query.sort(inserted_at: :asc)
      |> Ash.read!(actor: user)

    by_id = Map.new(cats, &{&1.id, &1})

    cats
    |> Enum.map(&Map.put(&1, :path, build_path(&1, by_id)))
    |> Enum.sort_by(fn cat ->
      {cat.kind != :inbox, Enum.map(cat.path, &String.downcase/1)}
    end)
  end

  @doc """
  Returns the id of the root ancestor of the category with the given id, walking
  up via `parent_id` in the given lookup map. Returns the input id if no parent
  is found (i.e. it's already a root).
  """
  def root_id(id, by_id) do
    case Map.get(by_id, id) do
      nil -> id
      %{parent_id: nil} -> id
      %{parent_id: parent_id} -> root_id(parent_id, by_id)
    end
  end

  defp build_path(cat, by_id), do: build_path_acc(cat, by_id, [])
  defp build_path_acc(nil, _by_id, acc), do: acc

  defp build_path_acc(cat, by_id, acc) do
    parent = if cat.parent_id, do: Map.get(by_id, cat.parent_id), else: nil
    build_path_acc(parent, by_id, [cat.name | acc])
  end
end
