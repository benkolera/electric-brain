defmodule Electricbrain.Repo.Migrations.MigrateNoteBodyDrawingToBlocks do
  @moduledoc """
  One-shot data move: notes used to carry exactly one markdown body and at
  most one drawing. The block editor turns those into ordered rows in
  `note_blocks`. Markdown gets position 0; sketch gets position 1 (or 0 if
  there was no body).

  Idempotency: each insert guards on NOT EXISTS for the same `(note_id, kind)`,
  so re-running on a partially-migrated DB is a no-op.

  Carries inserted_at/updated_at from the parent so historical sort order is
  preserved on the blocks page.
  """

  use Ecto.Migration

  def up do
    execute """
    INSERT INTO note_blocks (
      id, user_id, note_id, position, kind, data,
      inserted_at, updated_at
    )
    SELECT
      gen_random_uuid(), n.user_id, n.id, 0, 'markdown',
      jsonb_build_object('body', n.body),
      n.inserted_at, n.updated_at
    FROM notes n
    WHERE n.body IS NOT NULL AND n.body <> ''
      AND NOT EXISTS (
        SELECT 1 FROM note_blocks
        WHERE note_id = n.id AND kind = 'markdown'
      )
    """

    execute """
    INSERT INTO note_blocks (
      id, user_id, note_id, position, kind, data,
      inserted_at, updated_at
    )
    SELECT
      gen_random_uuid(), n.user_id, n.id,
      CASE WHEN n.body IS NOT NULL AND n.body <> '' THEN 1 ELSE 0 END,
      'sketch',
      jsonb_build_object('drawing', n.drawing),
      n.inserted_at, n.updated_at
    FROM notes n
    WHERE n.drawing IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM note_blocks
        WHERE note_id = n.id AND kind = 'sketch'
      )
    """
  end

  def down do
    execute """
    DELETE FROM note_blocks
    WHERE kind IN ('markdown', 'sketch')
    """
  end
end
