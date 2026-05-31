defmodule Electricbrain.DevicesTest do
  use Electricbrain.DataCase, async: false

  require Ash.Query

  alias Electricbrain.Devices
  alias Electricbrain.Devices.Pairing
  alias Electricbrain.Devices.PairingCode

  setup do
    user = create_user!()
    :ok = Electricbrain.Categories.seed_defaults_for(user)
    {:ok, user: user}
  end

  describe "generate_code!/1" do
    test "creates a 6-char code that expires in the future", %{user: user} do
      code = Devices.generate_code!(user)

      assert String.length(code.code) == 6
      assert DateTime.compare(code.expires_at, DateTime.utc_now()) == :gt
      assert code.user_id == user.id
    end

    test "destroys prior unconsumed codes so only the latest is live", %{user: user} do
      first = Devices.generate_code!(user)
      _second = Devices.generate_code!(user)

      assert {:error, _} = Ash.get(PairingCode, first.id, actor: user)

      live =
        PairingCode
        |> Ash.Query.filter(user_id == ^user.id)
        |> Ash.read!(actor: user)

      assert length(live) == 1
    end
  end

  describe "redeem_code/2" do
    test "exchanges a valid code for a token + pairing tied to the issuing user",
         %{user: user} do
      code = Devices.generate_code!(user)

      assert {:ok, %{pairing: pairing, token: token}} =
               Devices.redeem_code(code.code, "Even Hub · iPhone")

      assert pairing.user_id == user.id
      assert pairing.label == "Even Hub · iPhone"
      assert is_binary(token)
      assert String.length(token) >= 32

      # Cleartext is not persisted — only the SHA-256 hash.
      assert pairing.token_hash != token

      # Code is gone.
      assert {:error, _} = Ash.get(PairingCode, code.id, actor: user)
    end

    test "rejects an unknown code" do
      assert {:error, :invalid} = Devices.redeem_code("ZZZZZZ", "x")
    end

    test "rejects (and destroys) an expired code", %{user: user} do
      code = Devices.generate_code!(user)

      # Backdate to past TTL via raw Ash seed-style write.
      expired_at = DateTime.add(DateTime.utc_now(), -60, :second)

      code
      |> Ash.Changeset.for_destroy(:destroy, %{}, actor: user)
      |> Ash.destroy!()

      # Recreate with a backdated expiry — we need to bypass the normal generate
      # which sets expires_at internally, so seed directly.
      Ash.Seed.seed!(PairingCode, %{
        code: "BACKDT",
        expires_at: expired_at,
        user_id: user.id
      })

      assert {:error, :expired} = Devices.redeem_code("BACKDT", "x")
      # And the row is cleaned up.
      assert PairingCode
             |> Ash.Query.filter(code == "BACKDT")
             |> Ash.read!(authorize?: false) == []
    end
  end

  describe "lookup_token/1" do
    test "returns the pairing + user for a known token and bumps last_seen_at",
         %{user: user} do
      code = Devices.generate_code!(user)
      {:ok, %{token: token, pairing: pairing}} = Devices.redeem_code(code.code, "phone")

      assert pairing.last_seen_at == nil

      assert {:ok, {looked_up, looked_user}} = Devices.lookup_token(token)
      assert looked_up.id == pairing.id
      assert looked_user.id == user.id

      reloaded = Ash.get!(Pairing, pairing.id, authorize?: false)
      assert reloaded.last_seen_at
    end

    test "returns :error for an unknown token" do
      assert :error = Devices.lookup_token("not-a-real-token")
    end
  end

  describe "policies" do
    test "a user can only see their own pairings and codes", %{user: u1} do
      u2 = create_user!()
      :ok = Electricbrain.Categories.seed_defaults_for(u2)

      u1_code = Devices.generate_code!(u1)
      {:ok, %{pairing: u1_pairing}} = Devices.redeem_code(u1_code.code, "u1 phone")

      u2_code = Devices.generate_code!(u2)
      {:ok, %{pairing: _u2_pairing}} = Devices.redeem_code(u2_code.code, "u2 phone")

      # Issue a second un-redeemed code for u1 so we have one of each.
      u1_live_code = Devices.generate_code!(u1)

      u1_codes = Ash.read!(PairingCode, actor: u1)
      u1_pairings = Ash.read!(Pairing, actor: u1)

      assert Enum.map(u1_codes, & &1.id) == [u1_live_code.id]
      assert Enum.map(u1_pairings, & &1.id) == [u1_pairing.id]
    end
  end

  describe "state_for/1" do
    test "shape includes now/next/focus/habits_today", %{user: user} do
      state = Devices.state_for(user)

      assert Map.has_key?(state, :now)
      assert Map.has_key?(state, :next)
      assert Map.has_key?(state, :focus)
      assert Map.has_key?(state, :habits_today)
      assert is_list(state.habits_today)
    end
  end
end
