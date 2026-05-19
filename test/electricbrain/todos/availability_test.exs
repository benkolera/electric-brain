defmodule Electricbrain.Todos.AvailabilityTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Categories
  alias Electricbrain.Todos.Availability
  alias Electricbrain.Todos.Todo

  setup do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    inbox = Categories.inbox_for(user)

    todo =
      Todo
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Walk dog", category_id: inbox.id},
        actor: user
      )
      |> Ash.create!()

    {:ok, user: user, todo: todo}
  end

  test "creates an availability window", %{user: user, todo: todo} do
    assert {:ok, availability} =
             Availability
             |> Ash.Changeset.for_create(
               :create,
               %{
                 todo_id: todo.id,
                 day_of_week: 3,
                 start_time: ~T[18:00:00],
                 end_time: ~T[19:00:00]
               },
               actor: user
             )
             |> Ash.create()

    assert availability.day_of_week == 3
    assert availability.user_id == user.id
  end

  test "rejects end_time <= start_time", %{user: user, todo: todo} do
    assert {:error, _} =
             Availability
             |> Ash.Changeset.for_create(
               :create,
               %{
                 todo_id: todo.id,
                 day_of_week: 3,
                 start_time: ~T[19:00:00],
                 end_time: ~T[18:00:00]
               },
               actor: user
             )
             |> Ash.create()
  end

  test "destroying a todo cascade-deletes its availabilities", %{user: user, todo: todo} do
    Availability
    |> Ash.Changeset.for_create(
      :create,
      %{
        todo_id: todo.id,
        day_of_week: 1,
        start_time: ~T[09:00:00],
        end_time: ~T[10:00:00]
      },
      actor: user
    )
    |> Ash.create!()

    assert length(Ash.read!(Availability, actor: user)) == 1

    Ash.destroy!(todo, actor: user)
    assert Ash.read!(Availability, actor: user) == []
  end

  test "non-owner cannot create against another user's todo", %{todo: todo} do
    bob = create_user!()

    assert {:error, _} =
             Availability
             |> Ash.Changeset.for_create(
               :create,
               %{
                 todo_id: todo.id,
                 day_of_week: 1,
                 start_time: ~T[09:00:00],
                 end_time: ~T[10:00:00]
               },
               actor: bob
             )
             |> Ash.create()
  end

  test "day_of_week must be 1-7", %{user: user, todo: todo} do
    assert {:error, _} =
             Availability
             |> Ash.Changeset.for_create(
               :create,
               %{
                 todo_id: todo.id,
                 day_of_week: 0,
                 start_time: ~T[09:00:00],
                 end_time: ~T[10:00:00]
               },
               actor: user
             )
             |> Ash.create()
  end
end
