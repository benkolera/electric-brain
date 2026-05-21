defmodule Electricbrain.Notes.NoteBlock do
  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.Notes,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "note_blocks"
    repo Electricbrain.Repo

    references do
      reference :note, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:note_id, :position, :kind, :data]
      change relate_actor(:user)
    end

    update :update do
      accept [:position, :kind, :data]
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
              parent: Electricbrain.Notes.Note, field: :note_id},
             on: [:create]

    validate Electricbrain.Notes.Validations.BlockData,
      on: [:create, :update]
  end

  attributes do
    uuid_primary_key :id

    attribute :position, :integer do
      allow_nil? false
      public? true
      default 0
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:markdown, :tldraw]
    end

    attribute :data, :map do
      allow_nil? false
      public? true
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    belongs_to :note, Electricbrain.Notes.Note do
      allow_nil? false
      public? true
    end
  end
end
