defmodule Electricbrain.Focus.Validations.OneActivePerUser do
  @moduledoc """
  Rejects creating a focus session for a user who already has one in an
  active state (`:running` or `:on_break`). The DB has a partial unique
  index as the hard guarantee; this validator gives a friendlier error
  message at the app layer before the constraint fires.
  """

  use Ash.Resource.Validation

  require Ash.Query

  @impl true
  def validate(_changeset, _opts, context) do
    actor = context.actor

    case actor do
      %{id: user_id} ->
        active =
          Electricbrain.Focus.Session
          |> Ash.Query.filter(user_id == ^user_id and status in [:running, :on_break])
          |> Ash.Query.limit(1)
          |> Ash.read!(actor: actor, authorize?: false)

        case active do
          [] -> :ok
          [_ | _] -> {:error, "you already have an active focus session"}
        end

      _ ->
        :ok
    end
  end
end
