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

  defp validate_kind(:excalidraw, data) do
    cond do
      not Map.has_key?(data, "snapshot") and not Map.has_key?(data, :snapshot) ->
        {:error, "excalidraw block requires a :snapshot key"}

      not Map.has_key?(data, "preview_svg_light") and not Map.has_key?(data, :preview_svg_light) ->
        {:error, "excalidraw block requires a :preview_svg_light key"}

      not Map.has_key?(data, "preview_svg_dark") and not Map.has_key?(data, :preview_svg_dark) ->
        {:error, "excalidraw block requires a :preview_svg_dark key"}

      true ->
        :ok
    end
  end

  defp validate_kind(_, _), do: :ok
end
