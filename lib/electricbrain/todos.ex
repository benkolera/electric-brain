defmodule Electricbrain.Todos do
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.Todos.Todo
    resource Electricbrain.Todos.Availability
  end
end
