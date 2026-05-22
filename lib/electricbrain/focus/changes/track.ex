defmodule Electricbrain.Focus.Changes.Track do
  @moduledoc """
  After-action change on `Focus.Session` create + update actions. Two
  responsibilities:

    * Broadcast the new session state on the user's PubSub topic so any
      connected LiveView updates immediately.
    * Notify `Focus.Scheduler` so it can re-arm / disarm its timer.

  Centralizing both here means every caller (LiveView, Scheduler itself,
  future code) keeps the two paths in sync without remembering to
  broadcast separately.
  """

  use Ash.Resource.Change

  alias Electricbrain.Focus.Scheduler

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, session ->
      Phoenix.PubSub.broadcast(
        Electricbrain.PubSub,
        Scheduler.topic(session.user_id),
        {:focus_session, session}
      )

      Scheduler.track(session)
      {:ok, session}
    end)
  end
end
