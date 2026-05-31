defmodule ElectricbrainWeb.Plugs.G2TokenAuth do
  @moduledoc """
  Reads an `Authorization: Bearer <token>` header, looks up the matching
  `Devices.Pairing` by SHA-256 hash, and assigns the resolved user as
  the actor for the downstream Ash actions. Touches the pairing's
  `last_seen_at` as a side effect (cheap, idempotent).

  Halts with 401 on missing / unknown tokens. Designed for the
  `/api/g2/*` scope only; do not pipe browser routes through here.
  """

  import Plug.Conn

  alias Electricbrain.Devices

  def init(opts), do: opts

  def call(conn, _opts) do
    case bearer_token(conn) do
      nil ->
        deny(conn)

      token ->
        case Devices.lookup_token(token) do
          {:ok, {pairing, user}} ->
            conn
            |> assign(:current_user, user)
            |> assign(:current_pairing, pairing)
            |> Ash.PlugHelpers.set_actor(user)

          :error ->
            deny(conn)
        end
    end
  end

  defp bearer_token(conn) do
    header_token(conn) || query_token(conn)
  end

  defp header_token(conn) do
    conn
    |> get_req_header("authorization")
    |> List.first()
    |> case do
      "Bearer " <> token -> String.trim(token)
      "bearer " <> token -> String.trim(token)
      _ -> nil
    end
  end

  # EventSource (and a handful of other client APIs) can't set custom
  # headers, so the bearer can also ride as `?access_token=...`. The
  # token still flows over TLS but it will land in ALB access logs;
  # only used by SSE today, and per-device tokens are revocable from
  # the Settings page.
  defp query_token(conn) do
    case fetch_query_params(conn).query_params do
      %{"access_token" => token} when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  defp deny(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, ~s({"error":"unauthorized"}))
    |> halt()
  end
end
