defmodule Electricbrain.Schedulable.Fragment do
  @moduledoc """
  Resource fragment that injects the schedulable shape — duration plus
  pre/post buffer minutes — into `Habit`, `TimeBlock`, and `Todo`. One
  place to add a field that should apply to all schedulables.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource

  attributes do
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
  end
end
