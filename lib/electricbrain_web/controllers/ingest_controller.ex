defmodule ElectricbrainWeb.IngestController do
  @moduledoc """
  Measurement ingest webhook — the device-agnostic endpoint a relay
  (Health Auto Export for the Hume scale, or any curl) POSTs body
  readings to. Auth is an `:ingest`-kind device token minted on the
  meal settings page. Parsing/mapping lives in `Meals.Ingest`.
  """

  use ElectricbrainWeb, :controller

  alias Electricbrain.Meals.Ingest

  def create(conn, params) do
    user = conn.assigns.current_user

    case Ingest.ingest(user, params) do
      {:ok, result} ->
        json(conn, %{
          created: result.created,
          duplicates: result.duplicates,
          skipped: result.skipped,
          unmapped: result.unmapped
        })

      {:error, :invalid_payload} ->
        conn
        |> put_status(422)
        |> json(%{error: "invalid_payload"})
    end
  end
end
