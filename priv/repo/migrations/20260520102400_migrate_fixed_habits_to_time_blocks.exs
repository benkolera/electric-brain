defmodule Electricbrain.Repo.Migrations.MigrateFixedHabitsToTimeBlocks do
  @moduledoc """
  One-shot data move: every `habits` row with `fixed_schedule=true`
  becomes a `time_blocks` row (preserving the same UUID), its
  availabilities become `time_block_availabilities`, and any
  `plan_entries` referencing those habits get re-pointed via
  `time_block_id` with `habit_id` nulled.

  UUIDs are preserved so external references (like Google event ids
  on planner entries) don't need rewriting and so child rows can
  carry their parent_id over verbatim.

  Idempotency: this filters on `fixed_schedule = true`, which after
  the column drop in a later migration will yield no rows, so a
  re-run on an already-migrated DB is a no-op (though the column
  drop migration prevents re-runs anyway).
  """

  use Ecto.Migration

  def up do
    # Copy fixed-schedule habits into time_blocks, preserving id.
    execute """
    INSERT INTO time_blocks (
      id, user_id, category_id, title,
      duration_minutes, buffer_before_minutes, buffer_after_minutes,
      weekly_target_minutes, target_kind,
      inserted_at, updated_at
    )
    SELECT
      id, user_id, category_id, title,
      duration_minutes, buffer_before_minutes, buffer_after_minutes,
      NULL, NULL,
      inserted_at, updated_at
    FROM habits
    WHERE fixed_schedule = true
    """

    # Copy their availabilities. habit_id and time_block_id share the
    # same UUID for moved rows, so the parent ref carries over.
    execute """
    INSERT INTO time_block_availabilities (
      id, user_id, time_block_id, day_of_week, start_time, end_time,
      inserted_at, updated_at
    )
    SELECT
      a.id, a.user_id, a.habit_id, a.day_of_week, a.start_time, a.end_time,
      a.inserted_at, a.updated_at
    FROM habit_availabilities a
    JOIN habits h ON a.habit_id = h.id
    WHERE h.fixed_schedule = true
    """

    # Re-point planner entries. The check constraint requires exactly
    # one of todo_id/habit_id/time_block_id; setting time_block_id
    # and nulling habit_id keeps it satisfied (assuming the entry
    # was previously habit-only, which it had to be).
    execute """
    UPDATE plan_entries
    SET time_block_id = habit_id, habit_id = NULL
    WHERE habit_id IN (SELECT id FROM habits WHERE fixed_schedule = true)
    """

    # Drop the old availabilities (FK is :delete_all but be explicit).
    execute """
    DELETE FROM habit_availabilities
    WHERE habit_id IN (SELECT id FROM habits WHERE fixed_schedule = true)
    """

    # Drop the moved habits themselves.
    execute """
    DELETE FROM habits WHERE fixed_schedule = true
    """
  end

  def down do
    # Reverse: copy time_blocks back to habits with fixed_schedule=true.
    # min_count and period stay NULL (they were NULL on the originals).
    execute """
    INSERT INTO habits (
      id, user_id, category_id, title,
      min_count, period, duration_minutes,
      buffer_before_minutes, buffer_after_minutes,
      fixed_schedule, identity_statement, minimum_viable_action,
      inserted_at, updated_at
    )
    SELECT
      id, user_id, category_id, title,
      NULL, NULL, duration_minutes,
      buffer_before_minutes, buffer_after_minutes,
      true, NULL, NULL,
      inserted_at, updated_at
    FROM time_blocks
    """

    execute """
    INSERT INTO habit_availabilities (
      id, user_id, habit_id, day_of_week, start_time, end_time,
      inserted_at, updated_at
    )
    SELECT
      id, user_id, time_block_id, day_of_week, start_time, end_time,
      inserted_at, updated_at
    FROM time_block_availabilities
    """

    execute """
    UPDATE plan_entries
    SET habit_id = time_block_id, time_block_id = NULL
    WHERE time_block_id IS NOT NULL
    """

    execute "DELETE FROM time_block_availabilities"
    execute "DELETE FROM time_blocks"
  end
end
