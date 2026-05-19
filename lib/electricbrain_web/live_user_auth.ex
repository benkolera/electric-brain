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
      {:cont, attach_timezone_hook(socket)}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:live_user_required, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, attach_timezone_hook(socket)}
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
end
