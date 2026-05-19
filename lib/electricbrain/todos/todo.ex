defmodule Electricbrain.Todos.Todo do
  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Todos,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "todos"
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
        :status,
        :priority,
        :due_at,
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
        :status,
        :priority,
        :due_at,
        :category_id,
        :duration_minutes,
        :buffer_before_minutes,
        :buffer_after_minutes
      ]

      require_atomic? false
    end

    update :toggle do
      accept []
      require_atomic? false

      change fn changeset, _ ->
        next =
          case Ash.Changeset.get_attribute(changeset, :status) do
            :done -> :pending
            _ -> :done
          end

        Ash.Changeset.change_attribute(changeset, :status, next)
      end
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

    attribute :status, :atom do
      public? true
      default :pending
      constraints one_of: [:pending, :in_progress, :done]
    end

    attribute :priority, :atom do
      public? true
      default :medium
      constraints one_of: [:low, :medium, :high]
    end

    attribute :due_at, :utc_datetime do
      public? true
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

    has_many :availabilities, Electricbrain.Todos.Availability
  end
end
