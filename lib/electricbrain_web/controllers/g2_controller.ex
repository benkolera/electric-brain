defmodule ElectricbrainWeb.G2Controller do
  @moduledoc """
  JSON endpoints used by the Trellis Even Hub plugin running on the
  user's phone, which bridges to the G2 glasses over BLE.

    * `POST /api/g2/pair`    — unauthenticated; trades a 6-char code for
                              a long-lived bearer token.
    * `GET  /api/g2/state`   — bearer; "what should the HUD show now?"
    * `POST /api/g2/touch`   — bearer; bumps `last_seen_at`.
    * `DELETE /api/g2/pairing` — bearer; self-revoke.
  """

  use ElectricbrainWeb, :controller

  require Logger

  alias Electricbrain.Agenda
  alias Electricbrain.Devices
  alias Electricbrain.Focus

  # Heartbeat well under the ALB's 120s idle timeout so the connection
  # never goes silent enough for the load balancer to close it.
  @heartbeat_ms 30_000

  def pair(conn, %{"code" => code} = params) do
    label = Map.get(params, "label", "Even Hub")

    case Devices.redeem_code(String.trim(code), String.slice(label, 0, 80)) do
      {:ok, %{pairing: pairing, token: token}} ->
        json(conn, %{token: token, label: pairing.label, pairing_id: pairing.id})

      {:error, :invalid} ->
        conn |> put_status(422) |> json(%{error: "invalid_code"})

      {:error, :expired} ->
        conn |> put_status(422) |> json(%{error: "expired_code"})
    end
  end

  def pair(conn, _params), do: conn |> put_status(400) |> json(%{error: "missing_code"})

  def state(conn, _params) do
    user = conn.assigns.current_user
    json(conn, Devices.state_for(user))
  end

  def touch(conn, _params) do
    # G2TokenAuth already touched last_seen_at as a side effect of the
    # lookup; the explicit endpoint exists so a plugin can ping without
    # asking for state data.
    json(conn, %{ok: true})
  end

  def unpair(conn, _params) do
    user = conn.assigns.current_user
    pairing = conn.assigns.current_pairing

    Ash.destroy!(pairing, actor: user)
    json(conn, %{ok: true})
  end

  @doc """
  Long-lived `text/event-stream` of change notifications. Subscribes
  to the actor's `Agenda` and `Focus` PubSub topics; pushes a
  signal-only `change` SSE event whenever either fires. Heartbeat
  comments every #{@heartbeat_ms}ms keep the ALB from closing the
  connection. The client uses each event to trigger its existing
  `/api/g2/state` fetch + diff path, so payload stays tiny.
  """
  def stream(conn, _params) do
    user = conn.assigns.current_user

    # Make sure the per-user agenda actor is alive so we'll actually
    # receive `:agenda_changed` messages on the topic.
    _ = Agenda.ensure_started(user.id)
    Phoenix.PubSub.subscribe(Electricbrain.PubSub, Agenda.topic(user.id))
    Phoenix.PubSub.subscribe(Electricbrain.PubSub, Focus.Scheduler.topic(user.id))
    Phoenix.PubSub.subscribe(Electricbrain.PubSub, Electricbrain.Training.topic(user.id))
    Phoenix.PubSub.subscribe(Electricbrain.PubSub, Devices.test_topic(user.id))

    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      # Hint to any in-path reverse proxy (e.g. nginx) to not buffer.
      # ALB doesn't read this but it's free insurance.
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    case emit_comment(conn, "connected") do
      {:ok, conn} -> sse_loop(conn)
      {:error, _} -> conn
    end
  end

  defp sse_loop(conn) do
    receive do
      {:agenda_changed, _} ->
        case emit_event(conn, "change", ~s({"reason":"agenda"})) do
          {:ok, conn} -> sse_loop(conn)
          {:error, _} -> conn
        end

      {:focus_session, _} ->
        case emit_event(conn, "change", ~s({"reason":"focus"})) do
          {:ok, conn} -> sse_loop(conn)
          {:error, _} -> conn
        end

      {:training_workout, _} ->
        case emit_event(conn, "change", ~s({"reason":"training"})) do
          {:ok, conn} -> sse_loop(conn)
          {:error, _} -> conn
        end

      :test_push ->
        case emit_event(conn, "change", ~s({"reason":"test"})) do
          {:ok, conn} -> sse_loop(conn)
          {:error, _} -> conn
        end

      _other ->
        # Some unrelated subscriber traffic on a shared inbox — ignore.
        sse_loop(conn)
    after
      @heartbeat_ms ->
        case emit_comment(conn, "ping") do
          {:ok, conn} -> sse_loop(conn)
          {:error, _} -> conn
        end
    end
  end

  defp emit_event(conn, event, data) do
    Plug.Conn.chunk(conn, "event: #{event}\ndata: #{data}\n\n")
  end

  defp emit_comment(conn, text) do
    Plug.Conn.chunk(conn, ": #{text}\n\n")
  end
end
