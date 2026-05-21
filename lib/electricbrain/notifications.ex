defmodule Electricbrain.Notifications do
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.Notifications.PushSubscription
  end
end
