defmodule Electricbrain.Habits.Reflection do
  @moduledoc """
  One reflection per habit per week — Atomic Habits ch. 20. Captures
  freeform notes about what worked / what to adjust plus a 1-5 difficulty
  rating (the Goldilocks signal from ch. 19, used later for "this habit
  was rated too hard 3 weeks running — scale it down?" suggestions).

  Upsert by (habit_id, week_start) so the Weekly Review page can save
  without tracking whether the row already exists.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Habits,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "habit_reflections"
    repo Electricbrain.Repo

    references do
      reference :habit, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      accept [:habit_id, :week_start, :notes, :difficulty]
      upsert? true
      upsert_identity :unique_habit_week
      upsert_fields [:notes, :difficulty]
      change relate_actor(:user)
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
              parent: Electricbrain.Habits.Habit, field: :habit_id},
             on: [:create]
  end

  attributes do
    uuid_primary_key :id

    attribute :week_start, :date do
      allow_nil? false
      public? true
    end

    attribute :notes, :string do
      public? true
    end

    # Goldilocks rating: 1 = too easy, 3 = just right, 5 = too hard.
    attribute :difficulty, :integer do
      public? true
      constraints min: 1, max: 5
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    belongs_to :habit, Electricbrain.Habits.Habit do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_habit_week, [:habit_id, :week_start]
  end
end
