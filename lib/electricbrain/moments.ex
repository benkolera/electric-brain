defmodule Electricbrain.Moments do
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.Moments.Moment
  end
end
