defmodule Electricbrain.Planner.Entry do
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
