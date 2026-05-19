defmodule Electricbrain.CategoriesTest do
  use Electricbrain.DataCase, async: true
  require Ash.Query

  alias Electricbrain.Categories
  alias Electricbrain.Categories.Category

  describe "list_with_paths/1" do
    test "returns categories with the inbox first, then by full path alphabetically" do
      user = create_user!()
      :ok = Categories.seed_defaults_for(user)

      # Add a nested category to verify path resolution
      health =
        Category
        |> Ash.Query.filter(name == "Health")
        |> Ash.read_one!(actor: user)

      Category
      |> Ash.Changeset.for_create(
        :create,
        %{name: "Exercise", parent_id: health.id},
        actor: user
      )
      |> Ash.create!()

      cats = Categories.list_with_paths(user)
      names = Enum.map(cats, & &1.name)

      assert hd(cats).kind == :inbox
      assert "Exercise" in names

      exercise = Enum.find(cats, &(&1.name == "Exercise"))
      assert exercise.path == ["Health", "Exercise"]
    end
  end

  describe "root_id/2" do
    test "walks up via parent_id to the root" do
      user = create_user!()
      :ok = Categories.seed_defaults_for(user)

      health =
        Category
        |> Ash.Query.filter(name == "Health")
        |> Ash.read_one!(actor: user)

      exercise =
        Category
        |> Ash.Changeset.for_create(
          :create,
          %{name: "Exercise", parent_id: health.id},
          actor: user
        )
        |> Ash.create!()

      running =
        Category
        |> Ash.Changeset.for_create(
          :create,
          %{name: "Running", parent_id: exercise.id},
          actor: user
        )
        |> Ash.create!()

      by_id = Map.new(Categories.list_with_paths(user), &{&1.id, &1})

      assert Categories.root_id(running.id, by_id) == health.id
      assert Categories.root_id(exercise.id, by_id) == health.id
      assert Categories.root_id(health.id, by_id) == health.id
    end

    test "returns the input id when unknown" do
      assert Categories.root_id("missing", %{}) == "missing"
    end
  end
end
