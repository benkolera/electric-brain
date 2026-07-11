defmodule ElectricbrainWeb.IngestControllerTest do
  use ElectricbrainWeb.ConnCase, async: true

  require Ash.Query

  alias Electricbrain.Devices
  alias Electricbrain.Meals.NutritionProfile
  alias Electricbrain.Metrics.Measurement
  alias Electricbrain.Metrics.Metric

  setup %{conn: conn} do
    user = create_user!()

    weight =
      Metric
      |> Ash.Changeset.for_create(:create, %{name: "Weight", unit: "kg"}, actor: user)
      |> Ash.create!()

    body_fat =
      Metric
      |> Ash.Changeset.for_create(:create, %{name: "Body fat", unit: "%"}, actor: user)
      |> Ash.create!()

    NutritionProfile
    |> Ash.Changeset.for_create(
      :create,
      %{weight_metric_id: weight.id, body_fat_metric_id: body_fat.id},
      actor: user
    )
    |> Ash.create!()

    %{token: token} = Devices.create_ingest_token!(user, "Test ingest")

    {:ok,
     conn: put_req_header(conn, "content-type", "application/json"),
     user: user,
     token: token,
     weight: weight,
     body_fat: body_fat}
  end

  defp post_json(conn, token, payload) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> post(~p"/api/ingest/measurements", payload)
  end

  test "rejects missing, unknown, and wrong-kind tokens", %{conn: conn, user: user} do
    assert conn
           |> post(~p"/api/ingest/measurements", %{})
           |> json_response(401)

    assert conn
           |> post_json("nope", %{})
           |> json_response(401)

    # A G2 pairing token must not authorise the ingest endpoint.
    {:ok, %{token: g2_token}} =
      Devices.generate_code!(user)
      |> then(&Devices.redeem_code(&1.code, "glasses"))

    assert conn
           |> post_json(g2_token, %{})
           |> json_response(401)
  end

  test "generic payload creates measurements on the mapped metrics", %{
    conn: conn,
    token: token,
    user: user,
    weight: weight,
    body_fat: body_fat
  } do
    payload = %{
      "measurements" => [
        %{"metric" => "weight", "value" => 82.5, "recorded_at" => "2026-07-09T07:12:00Z"},
        %{"metric" => "body_fat_pct", "value" => 18.2, "recorded_at" => "2026-07-09T07:12:00Z"}
      ]
    }

    assert %{"created" => 2, "duplicates" => 0, "unmapped" => []} =
             conn |> post_json(token, payload) |> json_response(200)

    [w] = Measurement |> Ash.Query.filter(metric_id == ^weight.id) |> Ash.read!(actor: user)
    assert Decimal.equal?(w.value, Decimal.new("82.5"))
    assert w.recorded_at == ~U[2026-07-09 07:12:00.000000Z]

    [bf] = Measurement |> Ash.Query.filter(metric_id == ^body_fat.id) |> Ash.read!(actor: user)
    assert Decimal.equal?(bf.value, Decimal.new("18.2"))
  end

  test "Health Auto Export payload parses, including offset dates", %{
    conn: conn,
    token: token,
    user: user,
    weight: weight
  } do
    payload = %{
      "data" => %{
        "metrics" => [
          %{
            "name" => "weight_body_mass",
            "units" => "kg",
            "data" => [
              %{"qty" => 82.5, "date" => "2026-07-09 07:12:00 +1000"},
              %{"qty" => 82.1, "date" => "2026-07-08 07:09:00 +1000"}
            ]
          }
        ]
      }
    }

    assert %{"created" => 2} = conn |> post_json(token, payload) |> json_response(200)

    readings = Measurement |> Ash.Query.filter(metric_id == ^weight.id) |> Ash.read!(actor: user)
    assert length(readings) == 2
    # +1000 offset converts to UTC.
    assert Enum.any?(readings, &(&1.recorded_at == ~U[2026-07-08 21:12:00.000000Z]))
  end

  test "duplicate posts are idempotent", %{conn: conn, token: token} do
    payload = %{
      "measurements" => [
        %{"metric" => "weight", "value" => 82.5, "recorded_at" => "2026-07-09T07:12:00Z"}
      ]
    }

    assert %{"created" => 1, "duplicates" => 0} =
             conn |> post_json(token, payload) |> json_response(200)

    assert %{"created" => 0, "duplicates" => 1} =
             conn |> post_json(token, payload) |> json_response(200)
  end

  test "unknown keys are reported, not stored", %{conn: conn, token: token} do
    payload = %{
      "measurements" => [
        %{"metric" => "vo2_max", "value" => 48.0, "recorded_at" => "2026-07-09T07:12:00Z"}
      ]
    }

    assert %{"created" => 0, "unmapped" => ["vo2_max"]} =
             conn |> post_json(token, payload) |> json_response(200)
  end

  test "accepts relay payloads beyond the old 8MB parser default", %{conn: conn, token: token} do
    # ~12MB of readings on an unmapped key — exercises the raised JSON
    # parser limit without writing 100k measurements.
    readings =
      for i <- 1..120_000 do
        %{"metric" => "padding_key", "value" => i * 1.0, "recorded_at" => "2026-07-09T07:12:00Z"}
      end

    payload = Jason.encode!(%{"measurements" => readings})
    assert byte_size(payload) > 8_000_000

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/ingest/measurements", payload)
      |> json_response(200)

    assert response["created"] == 0
    assert response["unmapped"] == ["padding_key"]
  end

  test "unparseable entries are skipped, not fatal (HAE min/avg/max metrics)", %{
    conn: conn,
    token: token,
    user: user,
    weight: weight
  } do
    # A realistic HAE export: weight (qty) alongside heart rate
    # (min/avg/max — no qty) and a point with a garbage date. Only the
    # weight readings land; the rest count as skipped.
    payload = %{
      "data" => %{
        "metrics" => [
          %{
            "name" => "weight_body_mass",
            "units" => "kg",
            "data" => [
              %{"qty" => 82.5, "date" => "2026-07-09 07:12:00 +1000"},
              %{"qty" => 82.1, "date" => "not-a-date"}
            ]
          },
          %{
            "name" => "heart_rate",
            "units" => "bpm",
            "data" => [
              %{"Min" => 48, "Avg" => 62, "Max" => 141, "date" => "2026-07-09 00:00:00 +1000"}
            ]
          },
          %{"units" => "count"}
        ]
      }
    }

    assert %{"created" => 1, "skipped" => 3, "unmapped" => []} =
             conn |> post_json(token, payload) |> json_response(200)

    [reading] =
      Electricbrain.Metrics.Measurement
      |> Ash.Query.filter(metric_id == ^weight.id)
      |> Ash.read!(actor: user)

    assert Decimal.equal?(reading.value, Decimal.new("82.5"))
  end

  test "incomplete generic entries are skipped with a count", %{conn: conn, token: token} do
    assert %{"created" => 0, "skipped" => 1} =
             conn
             |> post_json(token, %{"measurements" => [%{"metric" => "weight"}]})
             |> json_response(200)
  end

  test "an unrecognisable envelope still gets 422", %{conn: conn, token: token} do
    assert %{"error" => "invalid_payload"} =
             conn
             |> post_json(token, %{"something" => "else"})
             |> json_response(422)
  end
end
