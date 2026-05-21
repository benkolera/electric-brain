defmodule Electricbrain.Moments.MomentTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Categories
  alias Electricbrain.Moments.Moment

  setup do
    user = create_user!()
    :ok = Categories.seed_defaults_for(user)
    inbox = Categories.inbox_for(user)
    {:ok, user: user, inbox: inbox}
  end

  describe "create/1" do
    test "creates a minimal moment (kind + name + intensity)", %{user: user, inbox: inbox} do
      assert {:ok, m} =
               Moment
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   kind: :craving,
                   name: "chocolate",
                   intensity: 4,
                   category_id: inbox.id
                 },
                 actor: user
               )
               |> Ash.create()

      assert m.kind == :craving
      assert m.name == "chocolate"
      assert m.intensity == 4
      assert m.user_id == user.id
      assert is_nil(m.recognize)
    end

    test "accepts the four RAIN journal fields", %{user: user, inbox: inbox} do
      assert {:ok, m} =
               Moment
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   kind: :feeling,
                   name: "anxious about the demo",
                   intensity: 5,
                   recognize: "tightness in my chest",
                   allow: "yes, it can be here",
                   investigate: "wants me to over-prepare",
                   nurture: "remind myself I've done this before",
                   category_id: inbox.id
                 },
                 actor: user
               )
               |> Ash.create()

      assert m.recognize == "tightness in my chest"
      assert m.allow == "yes, it can be here"
      assert m.investigate == "wants me to over-prepare"
      assert m.nurture == "remind myself I've done this before"
    end

    test "rejects an unknown kind", %{user: user, inbox: inbox} do
      assert {:error, _} =
               Moment
               |> Ash.Changeset.for_create(
                 :create,
                 %{kind: :weird, name: "x", intensity: 1, category_id: inbox.id},
                 actor: user
               )
               |> Ash.create()
    end

    test "rejects intensity outside 1..5", %{user: user, inbox: inbox} do
      assert {:error, _} =
               Moment
               |> Ash.Changeset.for_create(
                 :create,
                 %{kind: :urge, name: "x", intensity: 0, category_id: inbox.id},
                 actor: user
               )
               |> Ash.create()

      assert {:error, _} =
               Moment
               |> Ash.Changeset.for_create(
                 :create,
                 %{kind: :urge, name: "x", intensity: 6, category_id: inbox.id},
                 actor: user
               )
               |> Ash.create()
    end

    test "is scoped to the actor", %{user: user, inbox: inbox} do
      {:ok, _} =
        Moment
        |> Ash.Changeset.for_create(
          :create,
          %{kind: :other, name: "mine", intensity: 2, category_id: inbox.id},
          actor: user
        )
        |> Ash.create()

      other = create_user!()
      assert Ash.read!(Moment, actor: other) == []
      assert length(Ash.read!(Moment, actor: user)) == 1
    end
  end
end
