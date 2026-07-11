defmodule Electricbrain.Training.Changes.Broadcast do
  @moduledoc """
  After-action change publishing `{:training_workout, record}` on the
  user's training topic — wakes the in-gym LiveView on other devices
  and the G2 SSE stream. The `Focus.Changes.Track` pattern minus the
  scheduler cast (no server-side timers fire on workouts).
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      Phoenix.PubSub.broadcast(
        Electricbrain.PubSub,
        Electricbrain.Training.topic(record.user_id),
        {:training_workout, record}
      )

      {:ok, record}
    end)
  end
end
