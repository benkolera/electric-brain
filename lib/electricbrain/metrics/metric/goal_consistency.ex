defmodule Electricbrain.Metrics.Metric.GoalConsistency do
  @moduledoc """
  Enforces the trio of period / goal_kind / goal_value:

    * `:sum` aggregation requires `period` (so the chart has a bucket size).
    * Setting either `goal_kind` or `goal_value` requires both, plus `period`
      (so the status pill has a well-defined current bucket).
  """

  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    aggregation = Ash.Changeset.get_attribute(changeset, :aggregation)
    period = Ash.Changeset.get_attribute(changeset, :period)
    goal_kind = Ash.Changeset.get_attribute(changeset, :goal_kind)
    goal_value = Ash.Changeset.get_attribute(changeset, :goal_value)

    cond do
      aggregation == :sum and is_nil(period) ->
        {:error, field: :period, message: "is required for summed metrics"}

      (not is_nil(goal_kind) or not is_nil(goal_value)) and
          (is_nil(goal_kind) or is_nil(goal_value)) ->
        {:error, field: :goal_value, message: "goal_kind and goal_value must be set together"}

      not is_nil(goal_kind) and is_nil(period) ->
        {:error, field: :period, message: "is required when a goal is set"}

      true ->
        :ok
    end
  end
end
