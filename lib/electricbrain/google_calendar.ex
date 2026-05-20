defmodule Electricbrain.GoogleCalendar do
  @moduledoc """
  Thin client for Google Calendar API v3. Handles OAuth token refresh, plus
  insert / update / delete of events on the user's primary calendar.

  One-way push: we never read events back. The user is the source of truth.
  """

  require Logger

  alias Electricbrain.Accounts.User

  @primary_calendar_id "primary"
  @oauth_token_url "https://oauth2.googleapis.com/token"
  @calendar_base "https://www.googleapis.com/calendar/v3"

  @doc """
  Returns true if the user has Google Calendar connected (has a refresh token).
  """
  def connected?(%User{google_refresh_token: token}) when is_binary(token), do: true
  def connected?(_), do: false

  @doc """
  Inserts or updates an event for the given Planner.Entry. Returns
  `{:ok, google_event_id}` on success.
  """
  def push_event(user, entry, opts \\ [])

  def push_event(user, entry, opts) do
    req = Keyword.get(opts, :req, default_req())

    with {:ok, user} <- ensure_fresh_token(user, req),
         {:ok, body} <- event_body(entry) do
      url =
        case entry.google_event_id do
          nil -> "#{@calendar_base}/calendars/#{@primary_calendar_id}/events"
          id -> "#{@calendar_base}/calendars/#{@primary_calendar_id}/events/#{id}"
        end

      method = if is_nil(entry.google_event_id), do: :post, else: :put

      case Req.request(req,
             method: method,
             url: url,
             headers: [{"authorization", "Bearer #{user.google_access_token}"}],
             json: body
           ) do
        {:ok, %{status: status, body: %{"id" => google_id}}} when status in 200..299 ->
          {:ok, google_id}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Google Calendar push failed: status=#{status} body=#{inspect(body)}")
          {:error, {:http, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Deletes the event from Google. No-op if the entry has no google_event_id.
  Returns `:ok` on success or `{:error, reason}`.
  """
  def delete_event(user, entry, opts \\ [])
  def delete_event(_user, %{google_event_id: nil}, _opts), do: :ok

  def delete_event(user, entry, opts) do
    req = Keyword.get(opts, :req, default_req())

    with {:ok, user} <- ensure_fresh_token(user, req) do
      url = "#{@calendar_base}/calendars/#{@primary_calendar_id}/events/#{entry.google_event_id}"

      case Req.request(req,
             method: :delete,
             url: url,
             headers: [{"authorization", "Bearer #{user.google_access_token}"}]
           ) do
        # 404 means already gone — treat as success for idempotency
        {:ok, %{status: status}} when status in [204, 200, 404, 410] -> :ok
        {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Lists events on the user's primary calendar between `time_min` and
  `time_max` (both `DateTime`). Single-events expansion is on, so
  recurring instances come back as individual events. Used by the
  orphan-cleanup tooling — see `Electricbrain.Calendar.Cleanup`.

  Returns `{:ok, [event_map]}` where each event map is the raw Google
  Calendar API representation (at minimum `"id"`, `"summary"`,
  `"start"`, `"end"`).
  """
  def list_events_for_range(user, %DateTime{} = time_min, %DateTime{} = time_max, opts \\ []) do
    req = Keyword.get(opts, :req, default_req())

    with {:ok, user} <- ensure_fresh_token(user, req) do
      url = "#{@calendar_base}/calendars/#{@primary_calendar_id}/events"

      params = [
        timeMin: DateTime.to_iso8601(time_min),
        timeMax: DateTime.to_iso8601(time_max),
        singleEvents: "true",
        maxResults: "2500"
      ]

      case Req.get(req,
             url: url,
             params: params,
             headers: [{"authorization", "Bearer #{user.google_access_token}"}]
           ) do
        {:ok, %{status: 200, body: %{"items" => items}}} ->
          {:ok, items}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Refreshes the access token via the refresh token if it's missing or about to
  expire (within 60 seconds). Returns `{:ok, updated_user}`.
  """
  def ensure_fresh_token(user, req \\ nil) do
    req = req || default_req()
    now = DateTime.utc_now()

    expired_or_soon =
      is_nil(user.google_access_token) or
        is_nil(user.google_token_expires_at) or
        DateTime.diff(user.google_token_expires_at, now, :second) < 60

    cond do
      not connected?(user) ->
        {:error, :not_connected}

      not expired_or_soon ->
        {:ok, user}

      true ->
        refresh(user, req)
    end
  end

  defp refresh(user, req) do
    client_id = Application.fetch_env!(:electricbrain, :google_client_id)
    client_secret = Application.fetch_env!(:electricbrain, :google_client_secret)

    case Req.post(req,
           url: @oauth_token_url,
           form: [
             client_id: client_id,
             client_secret: client_secret,
             refresh_token: user.google_refresh_token,
             grant_type: "refresh_token"
           ]
         ) do
      {:ok, %{status: 200, body: %{"access_token" => access_token, "expires_in" => expires_in}}} ->
        expires_at = DateTime.add(DateTime.utc_now(), expires_in - 5, :second)

        user
        |> Ash.Changeset.for_update(
          :refresh_google_tokens,
          %{google_access_token: access_token, google_token_expires_at: expires_at},
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

  defp event_body(entry) do
    schedulable = entry.todo || entry.habit

    cond do
      is_nil(entry.planned_at) ->
        {:error, :not_scheduled}

      is_nil(schedulable) ->
        {:error, :no_target}

      true ->
        # Per-entry override beats the schedulable's default (see
        # Planner.Entry.duration_minutes — fixed-schedule habits like
        # Sleep snapshot their availability window length onto the
        # entry, and the habit itself has nil duration_minutes).
        duration_minutes =
          entry.duration_minutes || schedulable.duration_minutes || 60

        start_dt = entry.planned_at
        end_dt = DateTime.add(start_dt, duration_minutes * 60, :second)

        title =
          cond do
            entry.todo -> entry.todo.title
            entry.habit -> entry.habit.title
            true -> "(untitled)"
          end

        {:ok,
         %{
           "summary" => title,
           "start" => %{"dateTime" => DateTime.to_iso8601(start_dt), "timeZone" => "UTC"},
           "end" => %{"dateTime" => DateTime.to_iso8601(end_dt), "timeZone" => "UTC"}
         }}
    end
  end

  defp default_req do
    Req.new(receive_timeout: 15_000, retry: false)
  end
end
