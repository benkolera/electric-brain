defmodule Electricbrain.Notifications.PushSubscriptionTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Notifications.PushSubscription

  defp valid_attrs do
    %{
      endpoint: "https://push.example.com/abc",
      p256dh_key: "p256dh-key",
      auth_key: "auth-key",
      user_agent: "Test Browser 1.0"
    }
  end

  test "creates a subscription scoped to the actor" do
    user = create_user!()

    assert {:ok, sub} =
             PushSubscription
             |> Ash.Changeset.for_create(:create, valid_attrs(), actor: user)
             |> Ash.create()

    assert sub.user_id == user.id
    assert sub.endpoint == "https://push.example.com/abc"
  end

  test "rejects duplicate endpoints for the same user" do
    user = create_user!()

    PushSubscription
    |> Ash.Changeset.for_create(:create, valid_attrs(), actor: user)
    |> Ash.create!()

    assert {:error, _} =
             PushSubscription
             |> Ash.Changeset.for_create(:create, valid_attrs(), actor: user)
             |> Ash.create()
  end

  test "two users can each have the same endpoint independently" do
    u1 = create_user!()
    u2 = create_user!()

    {:ok, _} =
      PushSubscription
      |> Ash.Changeset.for_create(:create, valid_attrs(), actor: u1)
      |> Ash.create()

    assert {:ok, _} =
             PushSubscription
             |> Ash.Changeset.for_create(:create, valid_attrs(), actor: u2)
             |> Ash.create()
  end

  test "policies hide a user's subscriptions from other users" do
    u1 = create_user!()
    u2 = create_user!()

    PushSubscription
    |> Ash.Changeset.for_create(:create, valid_attrs(), actor: u1)
    |> Ash.create!()

    assert Ash.read!(PushSubscription, actor: u2) == []
    assert length(Ash.read!(PushSubscription, actor: u1)) == 1
  end
end
