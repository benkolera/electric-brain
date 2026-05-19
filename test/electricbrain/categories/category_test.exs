defmodule Electricbrain.Categories.CategoryTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Categories.Category

  describe "create/1" do
    test "creates a root category for the actor" do
      user = create_user!()

      assert {:ok, category} =
               Category
               |> Ash.Changeset.for_create(:create, %{name: "Health"}, actor: user)
               |> Ash.create()

      assert category.name == "Health"
      assert category.parent_id == nil
      assert category.user_id == user.id
    end

    test "creates a child category under a parent" do
      user = create_user!()
      {:ok, parent} = create_category(user, "Health")

      assert {:ok, child} =
               Category
               |> Ash.Changeset.for_create(
                 :create,
                 %{name: "Exercise", parent_id: parent.id},
                 actor: user
               )
               |> Ash.create()

      assert child.parent_id == parent.id
    end

    test "requires an actor" do
      assert {:error, _} =
               Category
               |> Ash.Changeset.for_create(:create, %{name: "Health"})
               |> Ash.create()
    end

    test "requires a name" do
      user = create_user!()

      assert {:error, _} =
               Category
               |> Ash.Changeset.for_create(:create, %{}, actor: user)
               |> Ash.create()
    end
  end

  describe "read policies" do
    test "user only sees their own categories" do
      alice = create_user!()
      bob = create_user!()

      {:ok, _alice_cat} = create_category(alice, "Alice's stuff")
      {:ok, _bob_cat} = create_category(bob, "Bob's stuff")

      alice_results = Category |> Ash.read!(actor: alice)
      assert length(alice_results) == 1
      assert hd(alice_results).name == "Alice's stuff"
    end
  end

  describe "update" do
    test "owner can rename" do
      user = create_user!()
      {:ok, category} = create_category(user, "Helth")

      assert {:ok, updated} =
               category
               |> Ash.Changeset.for_update(:update, %{name: "Health"}, actor: user)
               |> Ash.update()

      assert updated.name == "Health"
    end

    test "non-owner cannot rename" do
      alice = create_user!()
      bob = create_user!()
      {:ok, category} = create_category(alice, "Alice's stuff")

      assert {:error, _} =
               category
               |> Ash.Changeset.for_update(:update, %{name: "Hijacked"}, actor: bob)
               |> Ash.update()
    end
  end

  describe "destroy" do
    test "owner can destroy a leaf category" do
      user = create_user!()
      {:ok, category} = create_category(user, "Health")

      assert :ok = Ash.destroy(category, actor: user)
    end

    test "destroy is blocked when category has children (FK restrict)" do
      user = create_user!()
      {:ok, parent} = create_category(user, "Health")
      {:ok, _child} = create_category(user, "Exercise", parent_id: parent.id)

      assert {:error, _} = Ash.destroy(parent, actor: user)
    end

    test "non-owner cannot destroy" do
      alice = create_user!()
      bob = create_user!()
      {:ok, category} = create_category(alice, "Alice's stuff")

      assert {:error, _} = Ash.destroy(category, actor: bob)
    end
  end

  defp create_category(user, name, opts \\ []) do
    attrs = Map.new([{:name, name} | opts])

    Category
    |> Ash.Changeset.for_create(:create, attrs, actor: user)
    |> Ash.create()
  end
end
