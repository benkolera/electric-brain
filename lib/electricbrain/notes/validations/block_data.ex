defmodule Electricbrain.Notes.Validations.BlockData do
  @moduledoc """
  Validates the `data` map on a NoteBlock matches the shape expected for its
  `kind`. Kept light: each kind asserts the required keys exist and have a
  plausible type. The form layer is responsible for shaping data; this is a
  safety net against direct API misuse.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    kind = Ash.Changeset.get_attribute(changeset, :kind)
    data = Ash.Changeset.get_attribute(changeset, :data) || %{}

    case validate_kind(kind, data) do
      :ok -> :ok
      {:error, message} -> {:error, field: :data, message: message}
    end
  end

  defp validate_kind(:markdown, data) do
    case Map.get(data, "body") || Map.get(data, :body) do
      body when is_binary(body) -> :ok
      _ -> {:error, "markdown block requires a string :body"}
    end
  end

  defp validate_kind(:sketch, data) do
    drawing = Map.get(data, "drawing") || Map.get(data, :drawing)

    cond do
      not is_map(drawing) ->
        {:error, "sketch block requires a :drawing map"}

      not is_list(Map.get(drawing, "strokes") || Map.get(drawing, :strokes)) ->
        {:error, "sketch block :drawing must have a strokes list"}

      true ->
        :ok
    end
  end

  defp validate_kind(_, _), do: :ok
end
