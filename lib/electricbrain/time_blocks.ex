defmodule Electricbrain.TimeBlocks do
  @moduledoc """
  Scheduled tracked time — Sleep, Work, etc. Distinct from Habits
  (behaviours): a TimeBlock is a recurring block of time the user
  wants to spend on a life area, with an optional weekly target
  (e.g. "at least 56h sleep", "at most 50h work"). Auto-primed onto
  the planner from availability windows; appears on Google Calendar
  the same way habit entries do.

  Carved out of `Electricbrain.Habits` (where these lived as habits
  with `fixed_schedule: true`) so habit-specific features like
  identity statements, streak heatmaps, and neglect scoring don't
  pollute the time-tracking domain — and vice versa.
  """
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.TimeBlocks.TimeBlock
    resource Electricbrain.TimeBlocks.Availability
  end
end
