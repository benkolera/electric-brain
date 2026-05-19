defmodule Electricbrain.Validations.OwnedParent do
  @moduledoc """
  Validates that the FK referenced by `:field` points at a record of `:parent`
  that the acting user is authorized to read. Used to stop a user attaching
  a child resource to someone else's parent (e.g. an Availability row whose
  habit_id points to a habit owned by a different user).
  """

  use Ash.Resource.Validation

  @impl true
  def init(opts) do
    cond do
      not is_atom(opts[:parent]) ->
        {:error, ":parent must be an Ash.Resource module"}

      not is_atom(opts[:field]) ->
        {:error, ":field must be an atom"}

      true ->
        {:ok, opts}
    end
  end

  @impl true
  def validate(changeset, opts, context) do
    case Ash.Changeset.get_attribute(changeset, opts[:field]) do
      nil ->
        :ok

      id ->
        case Ash.get(opts[:parent], id, actor: context.actor) do
          {:ok, _record} -> :ok
          _ -> {:error, field: opts[:field], message: "must be your own #{opts[:parent]}"}
        end
    end
  end
end
