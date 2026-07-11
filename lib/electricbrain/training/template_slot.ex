defmodule Electricbrain.Training.TemplateSlot do
  @moduledoc """
  One ordered slot in a session template:

    * `:fixed` — a pinned exercise with the full prescription shape
      (`sets` × `reps`; e.g. squat 5×5, deadlift 1×5)
    * `:accessory` — a rotation marker filled from the accessory pool
      (exercises with `progression: :reps`) at generation time; only
      `sets` is used, target reps come from the exercise's state

  Modelling accessories as markers keeps rotation stateless and
  deterministic (the generator walks the pool by completed-session
  count); to pin an accessory, switch the slot to `:fixed`.
  """

  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Training,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "training_template_slots"
    repo Electricbrain.Repo

    references do
      reference :template, on_delete: :delete
      reference :exercise, on_delete: :restrict
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:template_id, :position, :kind, :exercise_id, :sets, :reps]

      change relate_actor(:user)
    end

    update :update do
      primary? true
      accept [:position, :kind, :exercise_id, :sets, :reps]
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
    validate {Electricbrain.Training.Validations.SlotExerciseConsistency, []}

    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Training.Template, field: :template_id} do
      where changing(:template_id)
    end

    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.Training.Exercise, field: :exercise_id} do
      where changing(:exercise_id)
    end

    validate compare(:sets, greater_than: 0) do
      where changing(:sets)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :position, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :kind, :atom do
      allow_nil? false
      default :fixed
      public? true
      constraints one_of: [:fixed, :accessory]
    end

    attribute :sets, :integer do
      allow_nil? false
      default 3
      public? true
    end

    attribute :reps, :integer do
      allow_nil? true
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :template, Electricbrain.Training.Template do
      allow_nil? false
      public? true
    end

    belongs_to :exercise, Electricbrain.Training.Exercise do
      allow_nil? true
      public? true
    end

    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end
  end
end
