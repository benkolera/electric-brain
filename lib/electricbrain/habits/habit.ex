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
        :buffer_after_minutes
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
        :buffer_after_minutes
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

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :min_count, :integer do
      allow_nil? false
      default 1
      public? true
      constraints min: 1
    end

    attribute :period, :atom do
      allow_nil? false
      default :week
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
  end
end
