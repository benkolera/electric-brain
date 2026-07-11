defmodule ElectricbrainWeb.OuraAuthController do
  @moduledoc """
  Per-user Oura OAuth2 flow (Oura retired personal access tokens in
  Dec 2025). Grants read access to daily activity summaries. Mirrors
  `GoogleOAuthController` — Auth0 is "who you are", this is "this user
  connected their ring".
  """

  use ElectricbrainWeb, :controller

  require Logger

  @authorize_url "https://cloud.ouraring.com/oauth/authorize"
  @token_url "https://api.ouraring.com/oauth/token"
  @scopes "daily"

  def start(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn |> put_flash(:error, "Sign in first") |> redirect(to: ~p"/sign-in")

      _user ->
        state = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)

        params =
          URI.encode_query(
            client_id: client_id(),
            redirect_uri: redirect_uri(conn),
            response_type: "code",
            scope: @scopes,
            state: state
          )

        conn
        |> put_session(:oura_oauth_state, state)
        |> redirect(external: @authorize_url <> "?" <> params)
    end
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        conn |> put_flash(:error, "Sign in first") |> redirect(to: ~p"/sign-in")

      state != get_session(conn, :oura_oauth_state) ->
        conn
        |> put_flash(:error, "OAuth state mismatch — please try again")
        |> redirect(to: ~p"/meals/settings")

      true ->
        case exchange_code_for_tokens(code, redirect_uri(conn)) do
          {:ok, tokens} ->
            user =
              user
              |> Ash.Changeset.for_update(:connect_oura, tokens, actor: user)
              |> Ash.update!()

            # Best-effort initial backfill so the TDEE basis flips as
            # soon as there's a week of data.
            case Electricbrain.Oura.Sync.sync_user(user) do
              {:ok, _count} -> :ok
              {:error, reason} -> Logger.warning("Initial Oura sync failed: #{inspect(reason)}")
            end

            conn
            |> delete_session(:oura_oauth_state)
            |> put_flash(:info, "Connected Oura")
            |> redirect(to: ~p"/meals/settings")

          {:error, reason} ->
            Logger.warning("Oura OAuth callback failed: #{inspect(reason)}")

            conn
            |> put_flash(:error, "Couldn't connect Oura")
            |> redirect(to: ~p"/meals/settings")
        end
    end
  end

  def callback(conn, %{"error" => error}) do
    conn
    |> put_flash(:error, "Oura denied access: #{error}")
    |> redirect(to: ~p"/meals/settings")
  end

  defp exchange_code_for_tokens(code, redirect_uri) do
    case Req.post(@token_url,
           form: [
             code: code,
             client_id: client_id(),
             client_secret: client_secret(),
             redirect_uri: redirect_uri,
             grant_type: "authorization_code"
           ]
         ) do
      {:ok,
       %{
         status: 200,
         body: %{
           "access_token" => access,
           "refresh_token" => refresh,
           "expires_in" => expires_in
         }
       }} ->
        {:ok,
         %{
           oura_access_token: access,
           oura_refresh_token: refresh,
           oura_token_expires_at: DateTime.add(DateTime.utc_now(), expires_in - 5, :second)
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp redirect_uri(conn) do
    url(conn, ~p"/oauth/oura/callback")
  end

  defp client_id, do: Application.fetch_env!(:electricbrain, :oura_client_id)
  defp client_secret, do: Application.fetch_env!(:electricbrain, :oura_client_secret)
end
