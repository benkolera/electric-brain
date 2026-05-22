defmodule Electricbrain.Focus.Session do
  @moduledoc """
  A single pomodoro-style focus session.

  Lifecycle: `:running` → `:on_break` → `:completed`. The user can also
  abandon at any active state, transitioning to `:abandoned`. End-of-work
  and end-of-break transitions are normally driven by
  `Electricbrain.Focus.Scheduler` (a GenServer firing `Process.send_after/2`),
  but the actions can be invoked directly by the user too (e.g. "skip
  break" jumps `:running → :completed` without going through `:on_break`).

  Target polymorphism mirrors `Planner.Entry` but with `category_id` added
  and the "exactly one" relaxed to "at most one" so freestanding sessions
  are allowed. A partial unique index on `user_id` (added in a manual
  migration) enforces at most one row in an active state per user.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Focus,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "focus_sessions"
    repo Electricbrain.Repo

    references do
      reference :todo, on_delete: :nilify
      reference :habit, on_delete: :nilify
      reference :time_block, on_delete: :nilify
      reference :category, on_delete: :nilify
    end

    check_constraints do
      check_constraint :user_id,
        name: "focus_sessions_at_most_one_target",
        check:
          "(todo_id IS NOT NULL)::int + (habit_id IS NOT NULL)::int + (time_block_id IS NOT NULL)::int + (category_id IS NOT NULL)::int <= 1",
        message: "must reference at most one of a todo, habit, time block, or category"
    end
  end

  actions do
    defaults [:read, :destroy]

    create :start do
      accept [
        :duration_minutes,
        :break_minutes,
        :todo_id,
        :habit_id,
        :time_block_id,
        :category_id
      ]

      change relate_actor(:user)
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
      change Electricbrain.Focus.Changes.Track
    end

    update :start_break do
      accept []
      require_atomic? false

      change set_attribute(:status, :on_break)
      change set_attribute(:break_started_at, &DateTime.utc_now/0)
      change Electricbrain.Focus.Changes.Track
    end

    update :complete do
      accept []
      require_atomic? false

      change set_attribute(:status, :completed)
      change set_attribute(:ended_at, &DateTime.utc_now/0)
      change Electricbrain.Focus.Changes.Track
    end

    update :abandon do
      accept []
      require_atomic? false

      change set_attribute(:status, :abandoned)
      change set_attribute(:ended_at, &DateTime.utc_now/0)
      change Electricbrain.Focus.Changes.Track
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
    validate Electricbrain.Focus.Validations.OneActivePerUser, on: [:create]

    # Each OwnedParent short-circuits when the FK is nil, so listing all
    # four is safe — only the one the user set is actually checked.
    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Todos.Todo, field: :todo_id},
             on: [:create]

    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Habits.Habit, field: :habit_id},
             on: [:create]

    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.TimeBlocks.TimeBlock, field: :time_block_id},
             on: [:create]

    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Categories.Category, field: :category_id},
             on: [:create]
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :running
      constraints one_of: [:running, :on_break, :completed, :abandoned]
    end

    attribute :duration_minutes, :integer do
      allow_nil? false
      public? true
      default 25
      constraints min: 1, max: 240
    end

    attribute :break_minutes, :integer do
      allow_nil? false
      public? true
      default 5
      constraints min: 0, max: 60
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :break_started_at, :utc_datetime_usec do
      public? true
    end

    attribute :ended_at, :utc_datetime_usec do
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

    belongs_to :category, Electricbrain.Categories.Category do
      allow_nil? true
      public? true
    end
  end
end
