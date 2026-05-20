defmodule Electricbrain.Calendar.Cleanup do
  @moduledoc """
  One-shot tooling to delete orphan Google Calendar events left behind
  by older versions of the planner that destroyed/unscheduled entries
  without pushing the corresponding delete to Google.

  The "orphan" definition: any event on the user's primary calendar
  whose `summary` matches one of the current week's entry titles but
  whose Google event ID is NOT pointed to by any of those entries'
  `google_event_id`. This is heuristic (matches by title) so any
  user-created event titled the same as a planner entry would also be
  matched — review the dry-run output before running with mode=:delete.

  Run via release eval against a deployed task:

      bin/benkolera_poncho eval \\
        'Electricbrain.Calendar.Cleanup.cleanup_week("you@example.com", "2026-05-18")'

  That's a dry run. To actually delete:

      bin/benkolera_poncho eval \\
        'Electricbrain.Calendar.Cleanup.cleanup_week("you@example.com", "2026-05-18", :delete)'
  """

  alias Electricbrain.Accounts.User
  alias Electricbrain.GoogleCalendar
  alias Electricbrain.Planner.Entry

  require Ash.Query
  require Logger

  @doc """
  Identifies and (optionally) deletes orphan Google Calendar events for
  the given user's specified week. `mode` is `:dry_run` (default) or
  `:delete`. Returns `{:ok, %{kept: n, orphans: [...], deleted: m}}`.
  """
  def cleanup_week(user_email, week_start_iso, mode \\ :dry_run)
      when mode in [:dry_run, :delete] do
    with {:ok, user} <- fetch_user(user_email),
         {:ok, week_start} <- Date.from_iso8601(week_start_iso),
         {:ok, entries} <- fetch_week_entries(user, week_start),
         {time_min, time_max} <- week_utc_range(week_start, user.timezone),
         {:ok, google_events} <- GoogleCalendar.list_events_for_range(user, time_min, time_max) do
      titles = MapSet.new(entries, &entry_title/1)
      kept_ids = MapSet.new(entries, & &1.google_event_id) |> MapSet.delete(nil)

      orphans =
        for event <- google_events,
            MapSet.member?(titles, event["summary"]),
            not MapSet.member?(kept_ids, event["id"]) do
          event
        end

      IO.puts(
        "Found #{length(orphans)} orphan(s) (of #{length(google_events)} Google events in range)"
      )

      for event <- orphans do
        IO.puts("  - #{event["id"]} #{event["summary"]} #{get_in(event, ["start", "dateTime"])}")
      end

      deleted =
        case mode do
          :delete -> Enum.count(orphans, &delete_event(user, &1))
          :dry_run -> 0
        end

      if mode == :delete do
        IO.puts("Deleted #{deleted} orphan(s).")
      else
        IO.puts("Dry run. Re-run with mode=:delete to actually delete.")
      end

      {:ok, %{kept: MapSet.size(kept_ids), orphans: orphans, deleted: deleted}}
    end
  end

  defp fetch_user(email) do
    User
    |> Ash.Query.for_read(:get_by_email, %{email: email})
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, {:user_not_found, email}}
      {:ok, user} -> {:ok, user}
      err -> err
    end
  end

  defp fetch_week_entries(user, week_start) do
    entries =
      Entry
      |> Ash.Query.filter(week_start == ^week_start)
      |> Ash.Query.load([:todo, :habit])
      |> Ash.read!(actor: user)

    {:ok, entries}
  end

  defp entry_title(%{todo: %{title: t}}) when is_binary(t), do: t
  defp entry_title(%{habit: %{title: t}}) when is_binary(t), do: t
  defp entry_title(_), do: "(untitled)"

  defp week_utc_range(week_start, tz) do
    # Local week is Mon 00:00 → next Mon 00:00 in the user's timezone.
    # Convert both ends to UTC so the Google query timeMin/timeMax line
    # up with what the planner UI considers "this week".
    start_local = DateTime.new!(week_start, ~T[00:00:00], tz)
    end_local = DateTime.new!(Date.add(week_start, 7), ~T[00:00:00], tz)
    {DateTime.shift_zone!(start_local, "Etc/UTC"), DateTime.shift_zone!(end_local, "Etc/UTC")}
  end

  defp delete_event(user, event) do
    # The id is what we'd have stored as google_event_id, so a synthetic
    # Entry-shaped struct works fine with GoogleCalendar.delete_event/2.
    case GoogleCalendar.delete_event(user, %{google_event_id: event["id"]}) do
      :ok ->
        true

      {:error, reason} ->
        Logger.warning(
          "Failed to delete orphan #{event["id"]} (#{event["summary"]}): #{inspect(reason)}"
        )

        false
    end
  end
end
