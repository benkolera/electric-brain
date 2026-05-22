defmodule Electricbrain.Focus do
  @moduledoc """
  Pomodoro-style focus sessions. A session is a single work block (default
  25 minutes) optionally followed by a break (default 5). Sessions are
  server-backed so all of the user's connected clients reflect the same
  state, and the scheduler fires end-of-work / end-of-break push
  notifications so the phone pings even with no open tab.

  A session may optionally target one of `todo / habit / time_block /
  category` (mutually exclusive — the DB check constraint enforces it).
  Freestanding sessions are fine too: nothing in particular, just "I'm
  focusing for 25 minutes".
  """

  use Ash.Domain, otp_app: :electricbrain

  resources do
    resource Electricbrain.Focus.Session
  end
end
