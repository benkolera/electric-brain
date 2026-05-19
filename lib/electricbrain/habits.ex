defmodule Electricbrain.Habits do
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.Habits.Habit
    resource Electricbrain.Habits.Completion
    resource Electricbrain.Habits.Availability
  end
end
