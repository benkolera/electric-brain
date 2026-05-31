defmodule ElectricbrainWeb.G2ControllerTest do
  use ElectricbrainWeb.ConnCase, async: false

  alias Electricbrain.Devices
  alias Electricbrain.Devices.Pairing

  setup do
    user = create_user!()
    :ok = Electricbrain.Categories.seed_defaults_for(user)
    {:ok, user: user}
  end

  defp pair!(user) do
    code = Devices.generate_code!(user)
    {:ok, %{token: token, pairing: pairing}} = Devices.redeem_code(code.code, "test phone")
    {token, pairing}
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  describe "POST /api/g2/pair" do
    test "exchanges a valid code for a token", %{conn: conn, user: user} do
      code = Devices.generate_code!(user)

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/g2/pair", %{"code" => code.code, "label" => "iPhone"})
        |> json_response(200)

      assert is_binary(resp["token"])
      assert resp["label"] == "iPhone"
      assert resp["pairing_id"]
    end

    test "rejects an invalid code with 422", %{conn: conn} do
      assert conn
             |> put_req_header("content-type", "application/json")
             |> post(~p"/api/g2/pair", %{"code" => "ZZZZZZ"})
             |> json_response(422) == %{"error" => "invalid_code"}
    end

    test "rejects a missing code with 400", %{conn: conn} do
      assert conn
             |> put_req_header("content-type", "application/json")
             |> post(~p"/api/g2/pair", %{})
             |> json_response(400) == %{"error" => "missing_code"}
    end
  end

  describe "GET /api/g2/state" do
    test "returns the user's now/next/focus/habits_today JSON when authenticated",
         %{conn: conn, user: user} do
      {token, _} = pair!(user)

      resp =
        conn
        |> auth(token)
        |> get(~p"/api/g2/state")
        |> json_response(200)

      assert Map.has_key?(resp, "now")
      assert Map.has_key?(resp, "next")
      assert Map.has_key?(resp, "focus")
      assert is_list(resp["habits_today"])
    end

    test "401 without a token", %{conn: conn} do
      assert conn |> get(~p"/api/g2/state") |> json_response(401) == %{"error" => "unauthorized"}
    end

    test "401 with an unknown token", %{conn: conn} do
      assert conn
             |> auth("garbage-token")
             |> get(~p"/api/g2/state")
             |> json_response(401) == %{"error" => "unauthorized"}
    end
  end

  describe "POST /api/g2/touch" do
    test "bumps last_seen_at and returns ok", %{conn: conn, user: user} do
      {token, pairing} = pair!(user)
      before = Ash.get!(Pairing, pairing.id, authorize?: false).last_seen_at

      assert conn |> auth(token) |> post(~p"/api/g2/touch") |> json_response(200) ==
               %{"ok" => true}

      after_ts = Ash.get!(Pairing, pairing.id, authorize?: false).last_seen_at
      assert after_ts
      if before, do: assert(DateTime.compare(after_ts, before) != :lt)
    end
  end

  describe "DELETE /api/g2/pairing" do
    test "self-revokes the pairing", %{conn: conn, user: user} do
      {token, pairing} = pair!(user)

      assert conn
             |> auth(token)
             |> delete(~p"/api/g2/pairing")
             |> json_response(200) == %{"ok" => true}

      assert {:error, _} = Ash.get(Pairing, pairing.id, authorize?: false)
    end
  end
end
