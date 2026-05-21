defmodule Electricbrain.Repo.Migrations.SplitExcalidrawPreviewThemes do
  @moduledoc """
  Excalidraw blocks used to carry a single `preview_svg`; we now store
  `preview_svg_light` and `preview_svg_dark` so the still preview matches the
  active theme. Copy the old field across as the light preview when it exists,
  leave dark empty (the next save in the editor populates both).

  Idempotent — re-runs only set keys that are missing.
  """

  use Ecto.Migration

  def up do
    execute """
    UPDATE note_blocks
    SET data =
      jsonb_build_object(
        'snapshot', COALESCE(data->'snapshot', '{}'::jsonb),
        'preview_svg_light', COALESCE(data->>'preview_svg_light', data->>'preview_svg', ''),
        'preview_svg_dark', COALESCE(data->>'preview_svg_dark', '')
      )
    WHERE kind = 'excalidraw'
    """
  end

  def down, do: :ok
end
