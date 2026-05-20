defmodule Electricbrain.Habits do
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.Habits.Habit
    resource Electricbrain.Habits.Completion
    resource Electricbrain.Habits.Availability
    resource Electricbrain.Habits.RitualStep
    resource Electricbrain.Habits.StepCheck
    resource Electricbrain.Habits.Reflection
  end
end
