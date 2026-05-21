defmodule Electricbrain.TimeBlocks.TimeBlock do
  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.TimeBlocks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    fragments: [Electricbrain.Schedulable.Fragment]

  postgres do
    table "time_blocks"
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
        :category_id,
        :duration_minutes,
        :buffer_before_minutes,
        :buffer_after_minutes,
        :weekly_target_minutes,
        :target_kind
      ]

      change relate_actor(:user)
    end

    update :update do
      accept [
        :title,
        :category_id,
        :duration_minutes,
        :buffer_before_minutes,
        :buffer_after_minutes,
        :weekly_target_minutes,
        :target_kind
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

    # Optional weekly target — interpreted via `target_kind`. nil
    # means no tracking; the planner just shows the block without a
    # drift indicator.
    attribute :weekly_target_minutes, :integer do
      public? true
      constraints min: 0
    end

    attribute :target_kind, :atom do
      public? true
      constraints one_of: [:at_least, :at_most]
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

    has_many :availabilities, Electricbrain.TimeBlocks.Availability
  end
end
