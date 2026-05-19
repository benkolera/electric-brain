defmodule Electricbrain.Todos.TodoTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Categories
  alias Electricbrain.Categories.Category
  alias Electricbrain.Todos.Todo

  describe "create/1" do
    test "creates a todo in the given category" do
      user = create_user!()
      :ok = Categories.seed_defaults_for(user)
      inbox = Categories.inbox_for(user)

      assert {:ok, todo} =
               Todo
               |> Ash.Changeset.for_create(
                 :create,
                 %{title: "Walk the dog", category_id: inbox.id},
                 actor: user
               )
               |> Ash.create()

      assert todo.category_id == inbox.id
      assert todo.user_id == user.id
    end

    test "requires a category" do
      user = create_user!()

      assert {:error, _} =
               Todo
               |> Ash.Changeset.for_create(:create, %{title: "No home"}, actor: user)
               |> Ash.create()
    end
  end

  describe "policies" do
    test "user only sees their own todos" do
      alice = create_user!()
      bob = create_user!()
      :ok = Categories.seed_defaults_for(alice)
      :ok = Categories.seed_defaults_for(bob)

      alice_inbox = Categories.inbox_for(alice)

      Todo
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Alice's todo", category_id: alice_inbox.id},
        actor: alice
      )
      |> Ash.create!()

      assert Todo |> Ash.read!(actor: bob) == []
      assert length(Todo |> Ash.read!(actor: alice)) == 1
    end
  end

  describe "category constraint" do
    test "cannot destroy a category that still has todos" do
      user = create_user!()
      :ok = Categories.seed_defaults_for(user)
      inbox = Categories.inbox_for(user)

      Todo
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Pinned to inbox", category_id: inbox.id},
        actor: user
      )
      |> Ash.create!()

      assert {:error, _} = Ash.destroy(inbox, actor: user)
    end
  end

  describe "Categories.seed_defaults_for/1" do
    test "creates 6 root categories including an Inbox" do
      user = create_user!()
      :ok = Categories.seed_defaults_for(user)

      cats = Category |> Ash.read!(actor: user)
      assert length(cats) == 6
      assert Enum.any?(cats, &(&1.kind == :inbox and &1.name == "Inbox"))
    end
  end
end
