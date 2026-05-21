defmodule Electricbrain.Planner.Entry.ClearNotifiedAt do
  @moduledoc """
  Resets `notified_at` to nil after the action commits so the cron
  scheduler will re-fire an upcoming-start notification next tick.

  Setting `notified_at` to nil via `force_change_attribute/3` is a no-op
  when the changeset's "original" notified_at is already nil — common
  because callers reuse a stale struct from before the scheduler set
  it. We side-step that by issuing a direct Ecto update against the
  committed record.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _cs, record ->
      import Ecto.Query, only: [from: 2]

      Electricbrain.Repo.update_all(
        from(e in "plan_entries", where: e.id == type(^record.id, :binary_id)),
        set: [notified_at: nil]
      )

      {:ok, %{record | notified_at: nil}}
    end)
  end
end
