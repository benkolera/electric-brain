defmodule ElectricbrainWeb.FocusLive.Index do
  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Focus.Session
  alias Electricbrain.Timezones

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Focus")
     |> assign(:sessions, list_sessions(user))
     |> assign(:today_summary, today_summary(user))}
  end

  defp list_sessions(user) do
    Session
    |> Ash.Query.filter(status in [:completed, :abandoned])
    |> Ash.Query.sort(ended_at: :desc)
    |> Ash.Query.load([:todo, :habit, :time_block, :category])
    |> Ash.read!(actor: user)
  end

  defp today_summary(user) do
    tz = user.timezone || "Etc/UTC"
    today_start = Timezones.period_start(:day, tz)

    sessions =
      Session
      |> Ash.Query.filter(status == :completed and ended_at >= ^today_start)
      |> Ash.read!(actor: user)

    minutes = sessions |> Enum.map(& &1.duration_minutes) |> Enum.sum()
    %{count: length(sessions), minutes: minutes}
  end

  defp group_by_day(sessions, tz) do
    sessions
    |> Enum.group_by(fn s ->
      s.ended_at
      |> DateTime.shift_zone!(tz)
      |> DateTime.to_date()
    end)
    |> Enum.sort_by(fn {date, _} -> date end, {:desc, Date})
  end

  defp day_label(date, tz) do
    today = DateTime.utc_now() |> DateTime.shift_zone!(tz) |> DateTime.to_date()

    cond do
      date == today -> "Today"
      Date.diff(today, date) == 1 -> "Yesterday"
      true -> Calendar.strftime(date, "%a %-d %b")
    end
  end

  defp target_label(%Session{todo: %{title: t}}), do: t
  defp target_label(%Session{habit: %{name: n}}), do: n
  defp target_label(%Session{time_block: %{name: n}}), do: n
  defp target_label(%Session{category: %{name: n}}), do: n
  defp target_label(_), do: "Freestanding"

  defp format_time(dt, tz) do
    dt |> DateTime.shift_zone!(tz) |> Calendar.strftime("%H:%M")
  end

  defp format_hhmm(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)
    :io_lib.format("~2..0B:~2..0B", [hours, mins]) |> IO.iodata_to_binary()
  end

  @impl true
  def render(assigns) do
    tz = assigns.current_user.timezone || "Etc/UTC"
    assigns = assign(assigns, :tz, tz)

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-end justify-between flex-wrap gap-3">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-primary">
            Focus
          </h1>
          <p class="text-sm text-neutral-content/70">
            Pomodoro sessions, grouped by day.
          </p>
        </div>
        <div class="text-right">
          <p class="text-xs uppercase tracking-wide text-neutral-content/60">Today</p>
          <p class="font-mono text-lg font-semibold">
            {@today_summary.count} session{if @today_summary.count == 1, do: "", else: "s"} · {format_hhmm(
              @today_summary.minutes
            )}
          </p>
        </div>
      </div>

      <%= if @sessions == [] do %>
        <div class="text-center py-12 text-neutral-content/60">
          No completed sessions yet — start one from the floating Focus pill.
        </div>
      <% else %>
        <div class="space-y-6">
          <%= for {date, day_sessions} <- group_by_day(@sessions, @tz) do %>
            <section>
              <h2 class="text-sm font-semibold text-neutral-content/80 mb-2">
                {day_label(date, @tz)}
              </h2>
              <ul class="space-y-1">
                <%= for session <- day_sessions do %>
                  <li class="flex items-center gap-3 py-1.5 px-2 rounded hover:bg-base-300/40 text-sm">
                    <span class="font-mono text-xs text-neutral-content/60 w-14">
                      {format_time(session.ended_at, @tz)}
                    </span>
                    <span class="font-medium truncate flex-1" title={target_label(session)}>
                      {target_label(session)}
                    </span>
                    <span class="font-mono text-xs text-neutral-content/60">
                      {format_hhmm(session.duration_minutes)}
                    </span>
                    <%= if session.status == :abandoned do %>
                      <span class="badge badge-ghost badge-sm">Abandoned</span>
                    <% else %>
                      <span class="badge badge-success badge-sm">Done</span>
                    <% end %>
                  </li>
                <% end %>
              </ul>
            </section>
          <% end %>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
