defmodule Electricbrain.OuraTest do
  use Electricbrain.DataCase, async: true

  require Ash.Query

  alias Electricbrain.Meals.Targets
  alias Electricbrain.Metrics.Measurement
  alias Electricbrain.Metrics.Metric
  alias Electricbrain.Oura

  setup do
    Application.put_env(:electricbrain, :oura_client_id, "test-client")
    Application.put_env(:electricbrain, :oura_client_secret, "test-secret")

    user = create_user!() |> connect_oura()

    {:ok, user: user}
  end

  defp connect_oura(user, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, 3600)

    user
    |> Ash.Changeset.for_update(
      :connect_oura,
      %{
        oura_access_token: Keyword.get(opts, :access_token, "at"),
        oura_refresh_token: Keyword.get(opts, :refresh_token, "rt"),
        oura_token_expires_at: DateTime.add(DateTime.utc_now(), expires_in, :second)
      },
      actor: user
    )
    |> Ash.update!()
  end

  defp activity_req(days) do
    Req.new(
      plug: fn conn ->
        assert conn.request_path == "/v2/usercollection/daily_activity"
        assert ["Bearer at"] = Plug.Conn.get_req_header(conn, "authorization")

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"data" => days}))
      end
    )
  end

  test "connected?/1", %{user: user} do
    assert Oura.connected?(user)
    refute Oura.connected?(create_user!())
  end

  test "daily_activity parses days", %{user: user} do
    req =
      activity_req([
        %{"day" => "2026-07-09", "active_calories" => 600, "total_calories" => 2900},
        %{"day" => "2026-07-10", "active_calories" => 450, "total_calories" => 2750}
      ])

    assert {:ok, [d1, d2]} = Oura.daily_activity(user, ~D[2026-07-09], ~D[2026-07-10], req: req)
    assert d1.day == ~D[2026-07-09]
    assert d1.total_calories == 2900
    assert d2.active_calories == 450
  end

  test "ensure_fresh_token refreshes an expired token and rotates the refresh token", %{
    user: user
  } do
    user = connect_oura(user, expires_in: 10)

    req =
      Req.new(
        plug: fn conn ->
          assert conn.request_path == "/oauth/token"
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert body =~ "grant_type=refresh_token"
          assert body =~ "refresh_token=rt"

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(
            200,
            Jason.encode!(%{
              "access_token" => "at2",
              "refresh_token" => "rt2",
              "expires_in" => 86_400
            })
          )
        end
      )

    assert {:ok, refreshed} = Oura.ensure_fresh_token(user, req)
    assert refreshed.oura_access_token == "at2"
    assert refreshed.oura_refresh_token == "rt2"
  end

  describe "Sync" do
    test "creates the kcal metrics and upserts measurements idempotently", %{user: user} do
      days = [
        %{"day" => "2026-07-09", "active_calories" => 600, "total_calories" => 2900},
        %{"day" => "2026-07-10", "active_calories" => 450, "total_calories" => 2750}
      ]

      assert {:ok, 4} = Oura.Sync.sync_user(user, req: activity_req(days))
      # Unchanged values: nothing rewritten.
      assert {:ok, 0} = Oura.Sync.sync_user(user, req: activity_req(days))

      # A corrected value updates in place.
      updated = List.update_at(days, 1, &Map.put(&1, "total_calories", 2800))
      assert {:ok, 1} = Oura.Sync.sync_user(user, req: activity_req(updated))

      total_metric =
        Metric |> Ash.Query.filter(name == "Oura total kcal") |> Ash.read_one!(actor: user)

      values =
        Measurement
        |> Ash.Query.filter(metric_id == ^total_metric.id)
        |> Ash.read!(actor: user)
        |> Enum.map(&Decimal.to_integer(&1.value))
        |> Enum.sort()

      assert values == [2800, 2900]
    end

    test "observed_tdee needs 7 days, then averages the trailing window", %{user: user} do
      days =
        for offset <- 1..5 do
          %{
            "day" => Date.to_iso8601(Date.add(Date.utc_today(), -offset)),
            "active_calories" => 500,
            "total_calories" => 2800
          }
        end

      {:ok, _} = Oura.Sync.sync_user(user, req: activity_req(days))
      assert :none = Oura.Sync.observed_tdee(user)

      more_days =
        for offset <- 1..9 do
          %{
            "day" => Date.to_iso8601(Date.add(Date.utc_today(), -offset)),
            "active_calories" => 500,
            "total_calories" => 2800
          }
        end

      {:ok, _} = Oura.Sync.sync_user(user, req: activity_req(more_days))
      assert {:ok, 2800} = Oura.Sync.observed_tdee(user)
    end
  end

  describe "adaptive TDEE in Targets" do
    test "observed_tdee replaces the formula and relaxes body inputs" do
      profile = %{
        height_cm: nil,
        birthdate: nil,
        sex: nil,
        activity_level: :moderate,
        goal: :cut,
        goal_rate_kcal_per_day: 400,
        protein_g_per_kg: Decimal.new("2.0"),
        fat_pct: Decimal.new(25)
      }

      assert {:error, :incomplete_profile} = Targets.compute(profile, 90.0, ~D[2026-07-11])

      assert {:ok, computed} =
               Targets.compute(profile, 90.0, ~D[2026-07-11], observed_tdee: 2800)

      assert computed.basis == :observed
      assert computed.tdee == 2800
      assert computed.kcal == 2400
      assert is_nil(computed.bmr)
    end

    test "formula basis is reported when no observation" do
      profile = %{
        height_cm: Decimal.new(180),
        birthdate: ~D[1991-03-15],
        sex: :male,
        activity_level: :moderate,
        goal: :maintain,
        goal_rate_kcal_per_day: 0,
        protein_g_per_kg: Decimal.new("2.0"),
        fat_pct: Decimal.new(25)
      }

      assert {:ok, computed} = Targets.compute(profile, 90.0, ~D[2026-07-11])
      assert computed.basis == :formula
      assert computed.bmr == 1855
    end
  end
end
