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

  alias Electricbrain.Devices

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
end
