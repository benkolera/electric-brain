defmodule Electricbrain.TimeBlocks.Availability do
  use Ash.Resource,
    otp_app: :electricbrain,
    domain: Electricbrain.TimeBlocks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "time_block_availabilities"
    repo Electricbrain.Repo

    references do
      reference :time_block, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:time_block_id, :day_of_week, :start_time, :end_time]
      change relate_actor(:user)
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type([:read, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  validations do
    validate {Electricbrain.Validations.OwnedParent,
              parent: Electricbrain.TimeBlocks.TimeBlock, field: :time_block_id},
             on: [:create]
  end

  attributes do
    uuid_primary_key :id

    # nil means "every day" — auto-prime expands into 1..7.
    attribute :day_of_week, :integer do
      public? true
      constraints min: 1, max: 7
    end

    attribute :start_time, :time do
      allow_nil? false
      public? true
    end

    attribute :end_time, :time do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Electricbrain.Accounts.User do
      allow_nil? false
    end

    belongs_to :time_block, Electricbrain.TimeBlocks.TimeBlock do
      allow_nil? false
      public? true
    end
  end

  @doc """
  Minutes between start_time and end_time. End <= start wraps past midnight, so
  22:00 → 06:00 is 480 minutes.
  """
  def duration_minutes(%{start_time: start_time, end_time: end_time}) do
    diff = Time.diff(end_time, start_time, :second)
    div(if(diff <= 0, do: diff + 86_400, else: diff), 60)
  end

  @doc "1 for a single-day window, 7 for an every-day (nil day_of_week) window."
  def occurrences_per_week(%{day_of_week: nil}), do: 7
  def occurrences_per_week(%{day_of_week: _}), do: 1
end
