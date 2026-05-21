defmodule Electricbrain.Repo.Migrations.DeleteLegacySketchBlocks do
  @moduledoc """
  One-shot cleanup: the legacy `:sketch` block kind was replaced by `:tldraw`.
  Existing `:sketch` rows otherwise render as "Unsupported block kind" stubs;
  drop them so old notes load clean.

  Idempotent — re-runs do nothing once the rows are gone.

  Irreversible by design: the old freehand-stroke shape doesn't map to a
  tldraw snapshot, so `down/0` is a no-op. If you somehow need them back,
  restore from a DB snapshot.
  """

  use Ecto.Migration

  def up do
    execute "DELETE FROM note_blocks WHERE kind = 'sketch'"
  end

  def down, do: :ok
end
