defmodule Electricbrain.Repo.Migrations.FocusSessionsActiveUniqueIndex do
  @moduledoc """
  Manual migration (no snapshot): partial unique index guaranteeing a user
  has at most one focus session in an active state (`:running` or
  `:on_break`) at a time. The app-layer validation
  `Electricbrain.Focus.Validations.OneActivePerUser` produces a friendlier
  error first; this index is the last-line race-condition guard.
  """

  use Ecto.Migration

  def up do
    create unique_index(
             :focus_sessions,
             [:user_id],
             where: "status IN ('running', 'on_break')",
             name: "focus_sessions_one_active_per_user"
           )
  end

  def down do
    drop_if_exists index(:focus_sessions, [:user_id], name: "focus_sessions_one_active_per_user")
  end
end
