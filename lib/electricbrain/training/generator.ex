defmodule Electricbrain.Training.Generator do
  @moduledoc """
  Pure, deterministic next-session prescription.

  Template alternation walks templates in `position` order, picking
  the one after the last COMPLETED workout's template (abandoning a
  session repeats it); a fresh user gets the first template.

  Accessory rotation is stateless: pool = reps-mode exercises sorted
  by name; accessory slot `i` of the session takes
  `pool[rem(completed_count * slots_per_session + i, length(pool))]`,
  which walks the pool evenly across sessions.
  """

  alias Electricbrain.Training.Progression

  @doc """
  Input:

    * `templates` — sorted by position, each `%{id, name, position,
      slots: [%{kind, exercise_id, exercise_name, sets, reps}]}`
      (slots sorted; exercise fields nil for accessory slots)
    * `last_template_position` — from the most recent completed
      workout, or nil for a fresh user
    * `completed_count` — all-time completed workouts (rotation clock)
    * `accessory_pool` — reps-mode `%{id, name}` sorted by name
    * `params_by_exercise_id`, `states_by_exercise_id`

  Output: `%{template: template, items: [%{exercise_id, exercise_name,
  slot_kind, sets, reps, weight_kg}]}` in slot order, or
  `{:error, :no_templates}`.
  """
  def next_session(%{templates: []}), do: {:error, :no_templates}

  def next_session(%{
        templates: templates,
        last_template_position: last_position,
        completed_count: completed_count,
        accessory_pool: accessory_pool,
        params_by_exercise_id: params_by_id,
        states_by_exercise_id: states_by_id
      }) do
    template = next_template(templates, last_position)
    accessory_slots = Enum.count(template.slots, &(&1.kind == :accessory))

    {items, _accessory_index} =
      Enum.map_reduce(template.slots, 0, fn slot, accessory_index ->
        case slot.kind do
          :fixed ->
            exercise = %{id: slot.exercise_id, name: slot.exercise_name}

            {item(slot, exercise, params_by_id[exercise.id], states_by_id[exercise.id]),
             accessory_index}

          :accessory ->
            exercise = rotate(accessory_pool, completed_count, accessory_slots, accessory_index)

            item =
              exercise &&
                item(slot, exercise, params_by_id[exercise.id], states_by_id[exercise.id])

            {item, accessory_index + 1}
        end
      end)

    %{template: template, items: Enum.reject(items, &is_nil/1)}
  end

  defp next_template(templates, nil), do: List.first(templates)

  defp next_template(templates, last_position) do
    Enum.find(templates, &(&1.position > last_position)) || List.first(templates)
  end

  defp rotate([], _completed, _per_session, _index), do: nil

  defp rotate(pool, completed_count, slots_per_session, index) do
    Enum.at(pool, rem(completed_count * slots_per_session + index, length(pool)))
  end

  defp item(_slot, _exercise, nil, _state), do: nil
  defp item(_slot, _exercise, _params, nil), do: nil

  defp item(slot, exercise, params, state) do
    prescription = Progression.prescription(params, state, %{sets: slot.sets, reps: slot.reps})

    %{
      exercise_id: exercise.id,
      exercise_name: exercise.name,
      slot_kind: slot.kind,
      sets: prescription.sets,
      reps: prescription.reps,
      weight_kg: prescription.weight_kg
    }
  end
end
