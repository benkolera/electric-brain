defmodule ElectricbrainWeb.GoogleOAuthController do
  @moduledoc """
  Per-user Google OAuth flow for Calendar API access. Distinct from Auth0
  login — Auth0 is "who you are", Google OAuth here is "this user has granted
  Calendar write access".
  """
  use ElectricbrainWeb, :controller

  require Logger

  @authorize_url "https://accounts.google.com/o/oauth2/v2/auth"
  @token_url "https://oauth2.googleapis.com/token"
  @userinfo_url "https://openidconnect.googleapis.com/v1/userinfo"
  @scopes "openid email https://www.googleapis.com/auth/calendar.events"

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
            access_type: "offline",
            prompt: "consent",
            state: state
          )

        conn
        |> put_session(:google_oauth_state, state)
        |> redirect(external: @authorize_url <> "?" <> params)
    end
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        conn |> put_flash(:error, "Sign in first") |> redirect(to: ~p"/sign-in")

      state != get_session(conn, :google_oauth_state) ->
        conn
        |> put_flash(:error, "OAuth state mismatch — please try again")
        |> redirect(to: ~p"/settings")

      true ->
        case exchange_code_for_tokens(code, redirect_uri(conn)) do
          {:ok, %{access_token: access, refresh: refresh, expires_at: expires_at, email: email}} ->
            user
            |> Ash.Changeset.for_update(
              :connect_google,
              %{
                google_email: email,
                google_access_token: access,
                google_refresh_token: refresh,
                google_token_expires_at: expires_at
              },
              actor: user
            )
            |> Ash.update!()

            conn
            |> delete_session(:google_oauth_state)
            |> put_flash(:info, "Connected Google Calendar (#{email})")
            |> redirect(to: ~p"/settings")

          {:error, reason} ->
            Logger.warning("Google OAuth callback failed: #{inspect(reason)}")

            conn
            |> put_flash(:error, "Couldn't connect Google Calendar")
            |> redirect(to: ~p"/settings")
        end
    end
  end

  def callback(conn, %{"error" => error}) do
    conn
    |> put_flash(:error, "Google denied access: #{error}")
    |> redirect(to: ~p"/settings")
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
         body:
           %{
             "access_token" => access,
             "refresh_token" => refresh,
             "expires_in" => expires_in
           } = body
       }} ->
        email = fetch_email(access, body)
        expires_at = DateTime.add(DateTime.utc_now(), expires_in - 5, :second)

        {:ok,
         %{
           access_token: access,
           refresh: refresh,
           expires_at: expires_at,
           email: email
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_email(access_token, token_body) do
    # email can come back in the id_token JWT, but easier: just call userinfo.
    case Req.get(@userinfo_url, headers: [{"authorization", "Bearer #{access_token}"}]) do
      {:ok, %{status: 200, body: %{"email" => email}}} ->
        email

      _ ->
        # Fall back to whatever scope info the token endpoint already gave us
        Map.get(token_body, "email", "unknown@google")
    end
  end

  defp client_id, do: Application.fetch_env!(:electricbrain, :google_client_id)
  defp client_secret, do: Application.fetch_env!(:electricbrain, :google_client_secret)

  defp redirect_uri(conn) do
    url(conn, ~p"/oauth/google/callback")
  end
end
