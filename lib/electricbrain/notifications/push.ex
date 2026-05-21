defmodule Electricbrain.Notifications.Push do
  @moduledoc """
  Sends a payload to one or many `PushSubscription`s using
  `WebPushElixir`. Wraps the library to:

    * Marshal our resource into the JSON shape the library expects.
    * Delete subscriptions that the push service reports as gone (404/410).
    * Encode the payload (title/body/url) as JSON so the service worker
      can `event.data.json()` it.
  """

  require Logger

  alias Electricbrain.Notifications.PushSubscription

  @doc """
  Sends a notification payload to a single subscription.
  Returns `:ok` on success, `:gone` if the subscription was deleted
  because the push service reported it as no longer valid, or
  `{:error, reason}` otherwise.
  """
  def send_to(%PushSubscription{} = sub, payload) when is_map(payload) do
    subscription_json =
      Jason.encode!(%{
        endpoint: sub.endpoint,
        keys: %{p256dh: sub.p256dh_key, auth: sub.auth_key}
      })

    message = Jason.encode!(payload)

    case WebPushElixir.send_notification(subscription_json, message) do
      {:ok, _response} ->
        :ok

      {:error, :expired} ->
        Ash.destroy!(sub, authorize?: false)
        :gone

      {:error, {:http_error, status, _body}} when status in [404, 410] ->
        Ash.destroy!(sub, authorize?: false)
        :gone

      {:error, reason} = err ->
        Logger.warning("Push send failed for #{sub.id}: #{inspect(reason)}")
        err
    end
  end

  @doc """
  Sends a payload to every subscription belonging to a user. Returns the
  count of successful sends.
  """
  def send_to_user(user, payload) when is_map(payload) do
    require Ash.Query

    PushSubscription
    |> Ash.Query.filter(user_id == ^user.id)
    |> Ash.read!(authorize?: false)
    |> Enum.reduce(0, fn sub, count ->
      case send_to(sub, payload) do
        :ok -> count + 1
        _ -> count
      end
    end)
  end
end
