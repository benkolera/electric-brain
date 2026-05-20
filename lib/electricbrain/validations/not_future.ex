defmodule Electricbrain.Validations.NotFuture do
  @moduledoc """
  Validates that the `utc_datetime_usec` (or `utc_datetime`) attribute named
  by `:field` is not strictly after `DateTime.utc_now/0`. Allows nil and
  same-instant values.
  """

  use Ash.Resource.Validation

  @impl true
  def init(opts) do
    if is_atom(opts[:field]) and not is_nil(opts[:field]) do
      {:ok, opts}
    else
      {:error, ":field must be an atom"}
    end
  end

  @impl true
  def validate(changeset, opts, _context) do
    case Ash.Changeset.get_attribute(changeset, opts[:field]) do
      nil ->
        :ok

      %DateTime{} = dt ->
        if DateTime.compare(dt, DateTime.utc_now()) == :gt do
          {:error, field: opts[:field], message: "must not be in the future"}
        else
          :ok
        end
    end
  end
end
