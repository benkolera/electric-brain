defmodule Electricbrain.Accounts do
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.Accounts.Token
    resource Electricbrain.Accounts.User
  end
end
