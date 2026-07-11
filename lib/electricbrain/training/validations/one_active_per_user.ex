defmodule Electricbrain.Training.Validations.OneActivePerUser do
  @moduledoc """
  Rejects starting a workout for a user who already has one `:active`.
  The DB has a partial unique index as the hard guarantee (manual
  migration); this gives a friendlier app-layer error first. Copy of
  `Electricbrain.Focus.Validations.OneActivePerUser`.
  """

  use Ash.Resource.Validation

  require Ash.Query

  @impl true
  def validate(_changeset, _opts, context) do
    case context.actor do
      %{id: user_id} ->
        active =
          Electricbrain.Training.Workout
          |> Ash.Query.filter(user_id == ^user_id and status == :active)
          |> Ash.Query.limit(1)
          |> Ash.read!(authorize?: false)

        case active do
          [] -> :ok
          [_ | _] -> {:error, "you already have an active workout"}
        end

      _ ->
        :ok
    end
  end
end
