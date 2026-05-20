defmodule Electricbrain.Habits.Habit do
  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Habits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "habits"
    repo Electricbrain.Repo

    references do
      reference :category, on_delete: :restrict
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :title,
        :min_count,
        :period,
        :category_id,
        :duration_minutes,
        :buffer_before_minutes,
        :buffer_after_minutes,
        :identity_statement,
        :minimum_viable_action
      ]

      change relate_actor(:user)
    end

    update :update do
      accept [
        :title,
        :min_count,
        :period,
        :category_id,
        :duration_minutes,
        :buffer_before_minutes,
        :buffer_after_minutes,
        :identity_statement,
        :minimum_viable_action
      ]

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
    validate present(:min_count), message: "is required"
    validate present(:period), message: "is required"
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :min_count, :integer do
      public? true
      allow_nil? false
      constraints min: 1
    end

    attribute :period, :atom do
      public? true
      constraints one_of: [:day, :week, :month]
    end

    attribute :duration_minutes, :integer do
      public? true
      constraints min: 0
    end

    attribute :buffer_before_minutes, :integer do
      public? true
      default 0
      allow_nil? false
      constraints min: 0
    end

    attribute :buffer_after_minutes, :integer do
      public? true
      default 0
      allow_nil? false
      constraints min: 0
    end

    # Atomic Habits ch. 2 — every completion is a vote for who you are.
    # Surface this on the planner when the habit is armed and on the
    # habit edit page; reinforces identity-based framing.
    attribute :identity_statement, :string do
      public? true
    end

    # Atomic Habits ch. 13 — the two-minute rule. A scaled-down version
    # of the habit to fall back on when energy/time is low, so the
    # streak doesn't break entirely. Shown as a hint, not a separate
    # completion mode (for now).
    attribute :minimum_viable_action, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    belongs_to :category, Electricbrain.Categories.Category do
      allow_nil? false
      public? true
    end

    has_many :completions, Electricbrain.Habits.Completion
    has_many :availabilities, Electricbrain.Habits.Availability
    has_many :ritual_steps, Electricbrain.Habits.RitualStep
    has_many :metric_links, Electricbrain.Metrics.HabitMetric

    many_to_many :metrics, Electricbrain.Metrics.Metric do
      through Electricbrain.Metrics.HabitMetric
      source_attribute_on_join_resource :habit_id
      destination_attribute_on_join_resource :metric_id
    end
  end
end
