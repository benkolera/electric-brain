defmodule Electricbrain.Planner.Entry do
  @moduledoc """
  A planner Entry pins a schedulable (todo / habit / time-block) to a week,
  optionally to a specific `planned_at`. The check constraint guarantees
  exactly one of `todo_id`, `habit_id`, `time_block_id` is set.

  ## Completion semantics (four overlapping concepts)

  The app tracks "did the user do this?" in four places, each with a
  different purpose. Knowing which fires when prevents UX bugs.

    * `Habits.Completion` (separate table) — one row per habit instance
      done. Drives the period streak count vs `habit.min_count`. Created
      from the habit page and from the home agenda's green check on a
      non-recurring habit entry.

    * `Todos.Todo.status` (enum `:pending | :in_progress | :done`) —
      lifecycle on the parent todo. For one-off todos, "done" means
      "permanently done". For recurring todos this would be the wrong
      semantic; the green-check on a recurring entry goes to
      `Entry.completed_at` instead, leaving the parent recurring.

    * `Planner.Entry.completed_at` — per-cycle / per-instance done.
      Hidden from agenda + planner views while the row stays in the DB
      so prime's dedup keeps holding. Cleared by `:uncomplete` if the
      user changes their mind.

    * `Metrics.Measurement` — numeric reading captured at the moment of
      completing a metric-attached habit. Not a "done" flag in itself
      but the artefact that the completion produced.

  When extending the planner, ask which of these is the right signal —
  more than one can fire for a single user action (completing a habit
  with an attached metric creates a Completion *and* a Measurement).
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Planner,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "plan_entries"
    repo Electricbrain.Repo

    references do
      reference :todo, on_delete: :delete
      reference :habit, on_delete: :delete
      reference :time_block, on_delete: :delete
    end

    check_constraints do
      check_constraint :todo_id,
        name: "plan_entries_exactly_one_target",
        check:
          "(todo_id IS NOT NULL)::int + (habit_id IS NOT NULL)::int + (time_block_id IS NOT NULL)::int = 1",
        message: "must reference exactly one of a todo, habit, or time block"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :week_start,
        :planned_at,
        :duration_minutes,
        :todo_id,
        :habit_id,
        :time_block_id
      ]

      change relate_actor(:user)
    end

    update :schedule do
      accept [:planned_at, :duration_minutes]
      require_atomic? false

      # Rescheduling re-arms the upcoming-start notification.
      change Electricbrain.Planner.Entry.ClearNotifiedAt
    end

    update :unschedule do
      accept []
      require_atomic? false

      change set_attribute(:planned_at, nil)
      change set_attribute(:google_event_id, nil)
      change Electricbrain.Planner.Entry.ClearNotifiedAt
    end

    update :mark_notified do
      accept []
      change set_attribute(:notified_at, &DateTime.utc_now/0)
    end

    update :set_google_event_id do
      accept [:google_event_id]
      require_atomic? false
    end

    # "Done this cycle" — keeps the row so prime won't recreate it, but
    # hides the entry from agenda/calendar views.
    update :complete do
      accept []
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change set_attribute(:dismissed_at, nil)
    end

    update :uncomplete do
      accept []
      change set_attribute(:completed_at, nil)
    end

    # "Skip this cycle" — same shape as complete but distinguishes
    # actively-done from intentionally-skipped in history.
    update :dismiss do
      accept []
      change set_attribute(:dismissed_at, &DateTime.utc_now/0)
      change set_attribute(:completed_at, nil)
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  validations do
    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Todos.Todo, field: :todo_id},
             on: [:create]

    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Habits.Habit, field: :habit_id},
             on: [:create]

    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.TimeBlocks.TimeBlock, field: :time_block_id},
             on: [:create]
  end

  attributes do
    uuid_primary_key :id

    attribute :week_start, :date do
      allow_nil? false
      public? true
    end

    attribute :planned_at, :utc_datetime_usec do
      public? true
    end

    # Per-entry override. Nil falls back to the schedulable's duration_minutes.
    # Set when the entry's length differs from the schedulable's default — e.g.
    # auto-primed fixed-schedule habits snapshot their availability window length.
    attribute :duration_minutes, :integer do
      public? true
      constraints min: 0
    end

    # Google Calendar event id, stored after a successful sync. Used to
    # update or delete the event idempotently on subsequent syncs.
    attribute :google_event_id, :string do
      public? true
    end

    # Set when the upcoming-start push notification has been fired for this
    # entry. Cleared on :schedule / :unschedule so a reschedule re-arms it.
    attribute :notified_at, :utc_datetime_usec do
      public? true
    end

    # "Done this cycle" for recurring todos (and any other entry the user
    # marks done from the agenda). The row stays so prime won't recreate
    # the entry within the same cycle; agenda/calendar views hide it.
    attribute :completed_at, :utc_datetime_usec do
      public? true
    end

    # "Skip this cycle" — same dedup effect as completed_at but tells history
    # the user explicitly chose not to do it.
    attribute :dismissed_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    belongs_to :todo, Electricbrain.Todos.Todo do
      allow_nil? true
      public? true
    end

    belongs_to :habit, Electricbrain.Habits.Habit do
      allow_nil? true
      public? true
    end

    belongs_to :time_block, Electricbrain.TimeBlocks.TimeBlock do
      allow_nil? true
      public? true
    end
  end
end
