defmodule Electricbrain.Training.Validations.ValidTrainingDays do
  @moduledoc """
  `training_days` must be a non-empty set of ISO day numbers (1–7,
  Monday–Sunday), no duplicates.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    days = Ash.Changeset.get_attribute(changeset, :training_days) || []

    cond do
      days == [] ->
        {:error, field: :training_days, message: "pick at least one training day"}

      Enum.any?(days, &(&1 not in 1..7)) ->
        {:error, field: :training_days, message: "days must be ISO day numbers 1–7"}

      length(Enum.uniq(days)) != length(days) ->
        {:error, field: :training_days, message: "days must not repeat"}

      true ->
        :ok
    end
  end
end
