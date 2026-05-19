defmodule Electricbrain.Planner do
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.Planner.Entry
  end
end
