defmodule Electricbrain.Notes.Note do
  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Notes,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "notes"
    repo Electricbrain.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title]
      change relate_actor(:user)
    end

    update :update do
      accept [:title]
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

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    has_many :blocks, Electricbrain.Notes.NoteBlock do
      sort position: :asc
    end
  end
end
