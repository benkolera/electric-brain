defmodule Electricbrain.Repo.Migrations.DeleteLegacyTldrawBlocks do
  @moduledoc """
  Drops any `:tldraw` rows left over from the brief tldraw experiment.
  The kind enum no longer accepts `:tldraw`, so stale rows would otherwise
  fail to load.

  Idempotent — re-runs are no-ops once the rows are gone. Irreversible:
  the tldraw snapshot format doesn't map to Excalidraw's.
  """

  use Ecto.Migration

  def up do
    execute "DELETE FROM note_blocks WHERE kind = 'tldraw'"
  end

  def down, do: :ok
end
