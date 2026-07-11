defmodule ElectricbrainWeb.TrainingLive.Settings do
  @moduledoc """
  Training preferences (days, reminder time, rest), the per-exercise
  table (current weight/reps — the starting-weights prompt — plus
  progression params), and a minimal template editor. Exercise rows
  save individually; template slots save per template via
  `manage_relationship(:direct_control)`.
  """

  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Training
  alias Electricbrain.Training.Template

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    :ok = Training.ensure_setup!(user)

    {:ok,
     socket
     |> assign(:page_title, "Training settings")
     |> load()}
  end

  defp load(socket) do
    user = socket.assigns.current_user

    socket
    |> assign(:settings, Training.settings_for(user))
    |> assign(:exercises, Training.exercises_for(user))
    |> assign(:templates, Training.templates_for(user))
  end

  @impl true
  def handle_event("save_settings", params, socket) do
    user = socket.assigns.current_user

    days =
      params
      |> Map.get("training_days", [])
      |> Enum.map(&String.to_integer/1)

    case socket.assigns.settings
         |> Ash.Changeset.for_update(
           :update,
           %{
             training_days: days,
             reminder_time: params["reminder_time"],
             default_rest_seconds: params["default_rest_seconds"]
           },
           actor: user
         )
         |> Ash.update() do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Training settings saved") |> load()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save — check the values")}
    end
  end

  def handle_event("save_exercise", %{"exercise_id" => id} = params, socket) do
    user = socket.assigns.current_user
    exercise = Enum.find(socket.assigns.exercises, &(&1.id == id))

    with {:ok, _} <-
           exercise
           |> Ash.Changeset.for_update(
             :update,
             %{
               increment_kg: blank_to_nil(params["increment_kg"]),
               rep_ceiling: blank_to_nil(params["rep_ceiling"]),
               rest_seconds: blank_to_nil(params["rest_seconds"])
             },
             actor: user
           )
           |> Ash.update(),
         {:ok, _} <-
           exercise.state
           |> Ash.Changeset.for_update(
             :update,
             %{
               current_weight_kg: blank_to_nil(params["current_weight_kg"]),
               current_reps: blank_to_nil(params["current_reps"])
             },
             actor: user
           )
           |> Ash.update() do
      {:noreply, socket |> put_flash(:info, "#{exercise.name} saved") |> load()}
    else
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save #{exercise.name}")}
    end
  end

  def handle_event("save_template", %{"template_id" => id} = params, socket) do
    user = socket.assigns.current_user
    template = Ash.get!(Template, id, actor: user)

    slots =
      params
      |> Map.get("slots", %{})
      |> Enum.sort_by(fn {index, _} -> String.to_integer(index) end)
      |> Enum.with_index()
      |> Enum.map(fn {{_index, slot}, position} ->
        kind = slot["kind"]

        %{
          position: position,
          kind: kind,
          exercise_id: if(kind == "fixed", do: blank_to_nil(slot["exercise_id"])),
          sets: slot["sets"],
          reps: if(kind == "fixed", do: blank_to_nil(slot["reps"]))
        }
      end)

    case template
         |> Ash.Changeset.for_update(:update, %{slots: slots}, actor: user)
         |> Ash.update() do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Template #{template.name} saved") |> load()}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not save template — fixed slots need an exercise and reps"
         )}
    end
  end

  def handle_event("add_slot", %{"template_id" => id}, socket) do
    user = socket.assigns.current_user
    template = Enum.find(socket.assigns.templates, &(&1.id == id))

    slots =
      Enum.map(
        template.slots,
        &%{
          position: &1.position,
          kind: &1.kind,
          exercise_id: &1.exercise_id,
          sets: &1.sets,
          reps: &1.reps
        }
      ) ++
        [
          %{
            position: length(template.slots),
            kind: :accessory,
            exercise_id: nil,
            sets: 3,
            reps: nil
          }
        ]

    template
    |> Ash.Changeset.for_update(:update, %{slots: slots}, actor: user)
    |> Ash.update!()

    {:noreply, load(socket)}
  end

  def handle_event("remove_slot", %{"template_id" => id, "index" => index}, socket) do
    user = socket.assigns.current_user
    template = Enum.find(socket.assigns.templates, &(&1.id == id))
    index = String.to_integer(index)

    slots =
      template.slots
      |> Enum.map(
        &%{
          position: &1.position,
          kind: &1.kind,
          exercise_id: &1.exercise_id,
          sets: &1.sets,
          reps: &1.reps
        }
      )
      |> List.delete_at(index)
      |> Enum.with_index()
      |> Enum.map(fn {slot, position} -> %{slot | position: position} end)

    template
    |> Ash.Changeset.for_update(:update, %{slots: slots}, actor: user)
    |> Ash.update!()

    {:noreply, load(socket)}
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp weight_str(nil), do: nil
  defp weight_str(decimal), do: decimal |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp time_value(%Time{} = t), do: t |> Time.to_string() |> String.slice(0, 5)

  @day_labels [{1, "Mon"}, {2, "Tue"}, {3, "Wed"}, {4, "Thu"}, {5, "Fri"}, {6, "Sat"}, {7, "Sun"}]
  defp day_labels, do: @day_labels

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-accent">
            Training settings
          </h1>
          <p class="text-sm text-neutral-content/70">
            Days, weights, progression parameters, and the A/B templates. All weights in kg.
          </p>
        </div>
        <.link navigate={~p"/training"} class="btn btn-ghost btn-sm">Back to training</.link>
      </div>

      <form phx-submit="save_settings" class="card bg-base-200 border border-base-300">
        <div class="card-body space-y-3">
          <h2 class="card-title">Schedule</h2>
          <div class="flex gap-3 flex-wrap items-end">
            <div>
              <label class="label"><span class="label-text text-xs">Training days</span></label>
              <div class="flex gap-3 flex-wrap">
                <label
                  :for={{day, label} <- day_labels()}
                  class="flex items-center gap-1 cursor-pointer text-sm"
                >
                  <input
                    type="checkbox"
                    name="training_days[]"
                    value={day}
                    checked={day in @settings.training_days}
                    class="checkbox checkbox-sm checkbox-primary"
                  /> {label}
                </label>
              </div>
            </div>
            <div>
              <label class="label"><span class="label-text text-xs">Reminder</span></label>
              <input
                type="time"
                name="reminder_time"
                value={time_value(@settings.reminder_time)}
                class="input input-bordered bg-base-100"
              />
            </div>
            <div>
              <label class="label">
                <span class="label-text text-xs">Rest between sets (s)</span>
              </label>
              <input
                type="number"
                name="default_rest_seconds"
                min="30"
                step="15"
                value={@settings.default_rest_seconds}
                class="input input-bordered bg-base-100 w-28"
              />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">Save</button>
          </div>
        </div>
      </form>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body space-y-1">
          <h2 class="card-title">Exercises</h2>
          <p class="text-sm text-neutral-content/70">
            Current weight/reps are what the next session prescribes — set your real working
            weights here. Editing a weight resets the stall count.
          </p>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Exercise</th>
                  <th>Weight kg</th>
                  <th>Reps</th>
                  <th>Increment kg</th>
                  <th>Rep ceiling</th>
                  <th>Rest s</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={exercise <- @exercises}>
                  <td colspan="7" class="p-0">
                    <form phx-submit="save_exercise" class="contents">
                      <input type="hidden" name="exercise_id" value={exercise.id} />
                      <div class="grid grid-cols-[1fr_repeat(5,minmax(4rem,6rem))_auto] gap-2 items-center py-1 px-2">
                        <span class="text-sm font-medium">
                          {exercise.name}
                          <span class="block text-xs font-normal text-neutral-content/50">
                            {exercise.progression}
                            <span :if={exercise.state.consecutive_stalls > 0}>
                              · {exercise.state.consecutive_stalls} stall(s)
                            </span>
                          </span>
                        </span>
                        <input
                          type="number"
                          step="0.5"
                          name="current_weight_kg"
                          value={weight_str(exercise.state.current_weight_kg)}
                          class="input input-bordered input-sm bg-base-100"
                        />
                        <input
                          type="number"
                          name="current_reps"
                          value={exercise.state.current_reps}
                          class="input input-bordered input-sm bg-base-100"
                        />
                        <input
                          type="number"
                          step="0.5"
                          name="increment_kg"
                          value={weight_str(exercise.increment_kg)}
                          class="input input-bordered input-sm bg-base-100"
                        />
                        <input
                          type="number"
                          name="rep_ceiling"
                          value={exercise.rep_ceiling}
                          class="input input-bordered input-sm bg-base-100"
                        />
                        <input
                          type="number"
                          name="rest_seconds"
                          value={exercise.rest_seconds}
                          placeholder={@settings.default_rest_seconds}
                          class="input input-bordered input-sm bg-base-100"
                        />
                        <button type="submit" class="btn btn-ghost btn-sm">Save</button>
                      </div>
                    </form>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div :for={template <- @templates} class="card bg-base-200 border border-base-300">
        <form phx-submit="save_template" class="card-body space-y-2">
          <input type="hidden" name="template_id" value={template.id} />
          <div class="flex items-center gap-2">
            <h2 class="card-title flex-1">Session {template.name}</h2>
            <button
              type="button"
              phx-click="add_slot"
              phx-value-template_id={template.id}
              class="btn btn-ghost btn-xs"
            >
              <.icon name="hero-plus-micro" class="size-4" /> Add slot
            </button>
            <button type="submit" class="btn btn-primary btn-sm">Save</button>
          </div>
          <div
            :for={{slot, index} <- Enum.with_index(template.slots)}
            class="flex gap-2 items-center flex-wrap"
          >
            <select
              name={"slots[#{index}][kind]"}
              class="select select-bordered select-sm bg-base-100"
            >
              <option value="fixed" selected={slot.kind == :fixed}>Fixed</option>
              <option value="accessory" selected={slot.kind == :accessory}>Accessory</option>
            </select>
            <select
              name={"slots[#{index}][exercise_id]"}
              class="select select-bordered select-sm bg-base-100 min-w-44"
            >
              <option value="">(rotates the accessory pool)</option>
              <option
                :for={exercise <- @exercises}
                value={exercise.id}
                selected={slot.exercise_id == exercise.id}
              >
                {exercise.name}
              </option>
            </select>
            <input
              type="number"
              name={"slots[#{index}][sets]"}
              value={slot.sets}
              min="1"
              class="input input-bordered input-sm bg-base-100 w-16"
              title="Sets"
            />
            <span class="text-xs text-neutral-content/50">×</span>
            <input
              type="number"
              name={"slots[#{index}][reps]"}
              value={slot.reps}
              min="1"
              placeholder="reps"
              class="input input-bordered input-sm bg-base-100 w-16"
              title="Reps (fixed slots)"
            />
            <button
              type="button"
              phx-click="remove_slot"
              phx-value-template_id={template.id}
              phx-value-index={index}
              class="btn btn-ghost btn-xs text-error"
            >
              <.icon name="hero-x-mark-micro" class="size-4" />
            </button>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
