defmodule Electricbrain.Notes.Changes.CleanupImageBlock do
  @moduledoc """
  After a NoteBlock is destroyed, delete any images it owned from ImageStore.
  Soft-fails on individual delete errors so an upstream cascade (e.g. the
  parent Note being destroyed) is never blocked by a missing S3 object.
  """

  use Ash.Resource.Change

  require Logger

  alias Electricbrain.Notes.Images

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, result ->
      if result.kind == :image do
        try do
          Images.delete(result.data || %{})
        rescue
          err ->
            Logger.warning("CleanupImageBlock: delete failed: #{inspect(err)}")
        end
      end

      {:ok, result}
    end)
  end
end
