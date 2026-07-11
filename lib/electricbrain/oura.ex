defmodule Electricbrain.Oura do
  @moduledoc """
  Thin client for the Oura API v2 (OAuth2 only — Oura retired personal
  access tokens in Dec 2025). Mirrors `Electricbrain.GoogleCalendar`:
  tokens live on the User, `ensure_fresh_token/2` refreshes on demand,
  and `req:` is injectable for tests.

  Oura rotates the refresh token on every refresh, so a refresh
  persists all three fields.
  """

  require Logger

  alias Electricbrain.Accounts.User

  @oauth_token_url "https://api.ouraring.com/oauth/token"
  @api_base "https://api.ouraring.com/v2"

  def connected?(%User{oura_refresh_token: token}) when is_binary(token), do: true
  def connected?(_), do: false

  @doc "True when OURA_CLIENT_ID/SECRET are configured (Settings degrades otherwise)."
  def configured? do
    is_binary(Application.get_env(:electricbrain, :oura_client_id)) and
      is_binary(Application.get_env(:electricbrain, :oura_client_secret))
  end

  @doc """
  Daily activity summaries between two local dates (inclusive).
  Returns `{:ok, [%{day: Date, active_calories: int, total_calories: int}]}`.
  """
  def daily_activity(user, %Date{} = start_date, %Date{} = end_date, opts \\ []) do
    req = Keyword.get(opts, :req, default_req())

    with {:ok, user} <- ensure_fresh_token(user, req) do
      case Req.get(req,
             url: "#{@api_base}/usercollection/daily_activity",
             params: [
               start_date: Date.to_iso8601(start_date),
               end_date: Date.to_iso8601(end_date)
             ],
             headers: [{"authorization", "Bearer #{user.oura_access_token}"}]
           ) do
        {:ok, %{status: 200, body: %{"data" => data}}} ->
          {:ok, Enum.map(data, &parse_day/1)}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Oura daily_activity failed: status=#{status} body=#{inspect(body)}")
          {:error, {:http, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp parse_day(day) do
    %{
      day: Date.from_iso8601!(day["day"]),
      active_calories: day["active_calories"] || 0,
      total_calories: day["total_calories"] || 0
    }
  end

  @doc """
  Refreshes the access token if missing or expiring within 60s.
  Returns `{:ok, user}` (possibly updated) or an error.
  """
  def ensure_fresh_token(user, req \\ nil) do
    req = req || default_req()
    now = DateTime.utc_now()

    expired_or_soon =
      is_nil(user.oura_access_token) or
        is_nil(user.oura_token_expires_at) or
        DateTime.diff(user.oura_token_expires_at, now, :second) < 60

    cond do
      not connected?(user) -> {:error, :not_connected}
      not expired_or_soon -> {:ok, user}
      true -> refresh(user, req)
    end
  end

  defp refresh(user, req) do
    case Req.post(req,
           url: @oauth_token_url,
           form: [
             client_id: Application.fetch_env!(:electricbrain, :oura_client_id),
             client_secret: Application.fetch_env!(:electricbrain, :oura_client_secret),
             refresh_token: user.oura_refresh_token,
             grant_type: "refresh_token"
           ]
         ) do
      {:ok, %{status: 200, body: %{"access_token" => access, "expires_in" => expires_in} = body}} ->
        expires_at = DateTime.add(DateTime.utc_now(), expires_in - 5, :second)

        user
        |> Ash.Changeset.for_update(
          :refresh_oura_tokens,
          %{
            oura_access_token: access,
            # Oura rotates refresh tokens; keep the old one if absent.
            oura_refresh_token: body["refresh_token"] || user.oura_refresh_token,
            oura_token_expires_at: expires_at
          },
          actor: user
        )
        |> Ash.update()
        |> case do
          {:ok, updated} -> {:ok, updated}
          {:error, reason} -> {:error, {:persist, reason}}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:refresh_http, status, body}}

      {:error, reason} ->
        {:error, {:refresh, reason}}
    end
  end

  defp default_req do
    Req.new(receive_timeout: 15_000, retry: false)
  end
end
