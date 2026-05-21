defmodule ElectricbrainWeb.AgendaHelpers do
  @moduledoc """
  Presentation helpers for `Electricbrain.Agenda` items
  (`%{entry:, end_time:, duration_minutes:}`) shared by the now-banner in
  `ElectricbrainWeb.Layouts` and the agenda view in `ElectricbrainWeb.HomeLive`.
  """

  def item_title(%{entry: entry}) do
    case Electricbrain.Planner.EntryTarget.title(entry) do
      "(untitled)" -> "Scheduled"
      title -> title
    end
  end

  def item_title(_), do: "Scheduled"

  def format_time_range(%{entry: %{planned_at: start}, end_time: finish}, tz) do
    tz = tz || "Etc/UTC"
    start_local = DateTime.shift_zone!(start, tz)
    end_local = DateTime.shift_zone!(finish, tz)

    if DateTime.to_date(start_local) == DateTime.to_date(end_local) do
      "#{Calendar.strftime(start_local, "%H:%M")}–#{Calendar.strftime(end_local, "%H:%M")}"
    else
      "#{Calendar.strftime(start_local, "%a %H:%M")} – #{Calendar.strftime(end_local, "%a %H:%M")}"
    end
  end

  def format_clock(dt, tz) do
    dt |> DateTime.shift_zone!(tz || "Etc/UTC") |> Calendar.strftime("%H:%M")
  end

  def format_hhmm(minutes) when is_integer(minutes) and minutes >= 0 do
    h = div(minutes, 60)
    m = rem(minutes, 60)
    :io_lib.format("~2..0B:~2..0B", [h, m]) |> IO.iodata_to_binary()
  end

  def minutes_remaining(%{end_time: end_time}) do
    diff = DateTime.diff(end_time, DateTime.utc_now(), :second)
    max(div(diff, 60), 0)
  end

  def minutes_until(%{entry: %{planned_at: start}}) do
    diff = DateTime.diff(start, DateTime.utc_now(), :second)
    max(div(diff, 60), 0)
  end
end
