defmodule ElectricbrainWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  import Phoenix.Component
  use ElectricbrainWeb, :verified_routes

  # This is used for nested liveviews to fetch the current user.
  # To use, place the following at the top of that liveview:
  # on_mount {ElectricbrainWeb.LiveUserAuth, :current_user}
  def on_mount(:current_user, _params, session, socket) do
    {:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont,
       socket
       |> attach_timezone_hook()
       |> attach_agenda(socket.assigns.current_user)
       |> attach_focus_session(socket.assigns.current_user)}
    else
      {:cont,
       socket
       |> assign(:current_user, nil)
       |> assign(:now_agenda, empty_agenda())
       |> assign(:focus_session, nil)}
    end
  end

  def on_mount(:live_user_required, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont,
       socket
       |> attach_timezone_hook()
       |> attach_agenda(socket.assigns.current_user)
       |> attach_focus_session(socket.assigns.current_user)}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  defp attach_timezone_hook(socket) do
    Phoenix.LiveView.attach_hook(
      socket,
      :timezone_sync,
      :handle_event,
      &handle_set_timezone/3
    )
  end

  defp handle_set_timezone("set_timezone", %{"timezone" => tz}, socket) do
    user = socket.assigns.current_user

    cond do
      not is_binary(tz) ->
        {:halt, socket}

      user.timezone == tz ->
        {:halt, socket}

      not Electricbrain.Timezones.valid?(tz) ->
        {:halt, socket}

      true ->
        case user
             |> Ash.Changeset.for_update(:set_timezone, %{timezone: tz}, actor: user)
             |> Ash.update() do
          {:ok, updated} -> {:halt, assign(socket, :current_user, updated)}
          _ -> {:halt, socket}
        end
    end
  end

  defp handle_set_timezone(_event, _params, socket), do: {:cont, socket}

  defp attach_agenda(socket, user) do
    if Phoenix.LiveView.connected?(socket) do
      snapshot =
        try do
          case Electricbrain.Agenda.subscribe(user.id) do
            {:ok, snap} -> snap
            _ -> empty_agenda()
          end
        rescue
          _ -> empty_agenda()
        end

      socket
      |> assign(:now_agenda, snapshot)
      |> Phoenix.LiveView.attach_hook(:agenda_sync, :handle_info, &handle_agenda_info/2)
    else
      assign(socket, :now_agenda, empty_agenda())
    end
  end

  defp handle_agenda_info({:agenda_changed, snapshot}, socket) do
    {:halt, assign(socket, :now_agenda, snapshot)}
  end

  defp handle_agenda_info(_msg, socket), do: {:cont, socket}

  defp empty_agenda, do: %{current: [], next: nil}

  defp attach_focus_session(socket, user) do
    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(
        Electricbrain.PubSub,
        Electricbrain.Focus.Scheduler.topic(user.id)
      )

      socket
      |> assign(:focus_session, load_active_focus_session(user))
      |> Phoenix.LiveView.attach_hook(:focus_sync, :handle_info, &handle_focus_info/2)
    else
      assign(socket, :focus_session, nil)
    end
  end

  defp load_active_focus_session(user) do
    require Ash.Query

    Electricbrain.Focus.Session
    |> Ash.Query.filter(status in [:running, :on_break])
    |> Ash.Query.limit(1)
    |> Ash.Query.load([:todo, :habit, :time_block, :category])
    |> Ash.read!(actor: user)
    |> List.first()
  end

  defp handle_focus_info({:focus_session, %{status: status} = session}, socket)
       when status in [:running, :on_break] do
    user = socket.assigns.current_user

    loaded =
      case Ash.load(session, [:todo, :habit, :time_block, :category], actor: user) do
        {:ok, s} -> s
        _ -> session
      end

    # Send_update reaches the LiveComponent reliably across the LV's
    # render boundary; assigning focus_session on the parent is also
    # done so any other consumer (e.g. nested layouts) sees it.
    Phoenix.LiveView.send_update(
      ElectricbrainWeb.FocusLive.Widget,
      id: "focus-widget",
      focus_session: loaded
    )

    {:halt, assign(socket, :focus_session, loaded)}
  end

  defp handle_focus_info({:focus_session, _completed_or_abandoned}, socket) do
    Phoenix.LiveView.send_update(
      ElectricbrainWeb.FocusLive.Widget,
      id: "focus-widget",
      focus_session: nil
    )

    {:halt, assign(socket, :focus_session, nil)}
  end

  defp handle_focus_info(_msg, socket), do: {:cont, socket}
end
