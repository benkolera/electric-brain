defmodule ElectricbrainWeb.TrainingLive.Session do
  @moduledoc """
  The in-gym screen: big tap targets, one card per exercise, sets as
  toggle chips. Tapping a set logs it at target reps (the common
  case); the − stepper on a logged set records fewer. Each log arms a
  client-side rest countdown (the Focus hook — server stays
  authoritative for everything persisted). Finish applies progression
  and Metrics; Abandon applies nothing.

  Subscribes to `Training.topic/1` so a second device stays in sync.
  """

  use ElectricbrainWeb, :live_view

  alias Electricbrain.Training
  alias Electricbrain.Training.WorkoutSet

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Electricbrain.PubSub, Training.topic(user.id))
    end

    case Training.active_workout(user) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/training")}

      workout ->
        {:ok,
         socket
         |> assign(:page_title, "Workout")
         |> assign(:settings, Training.settings_for(user))
         |> assign(:workout, workout)
         |> assign(:rest_ends_at, nil)}
    end
  end

  @impl true
  def handle_event("toggle_set", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    set = Enum.find(socket.assigns.workout.sets, &(&1.id == id))

    {action, params} =
      if set.completed_at, do: {:unlog, %{}}, else: {:log, %{actual_reps: set.target_reps}}

    set
    |> Ash.Changeset.for_update(action, params, actor: user)
    |> Ash.update!()

    {:noreply,
     socket
     |> assign(:rest_ends_at, if(action == :log, do: rest_ends_at(socket, set)))
     |> reload()}
  end

  def handle_event("decrement_set", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    set = Enum.find(socket.assigns.workout.sets, &(&1.id == id))

    if not is_nil(set.completed_at) and set.actual_reps > 0 do
      set
      |> Ash.Changeset.for_update(:log, %{actual_reps: set.actual_reps - 1}, actor: user)
      |> Ash.update!()
    end

    {:noreply, reload(socket)}
  end

  def handle_event("finish", _params, socket) do
    user = socket.assigns.current_user
    Training.complete_workout!(user, socket.assigns.workout)

    {:noreply,
     socket
     |> put_flash(:info, "Workout done — progression applied")
     |> push_navigate(to: ~p"/training")}
  end

  def handle_event("abandon", _params, socket) do
    user = socket.assigns.current_user
    Training.abandon_workout!(user, socket.assigns.workout)

    {:noreply,
     socket
     |> put_flash(:info, "Workout abandoned — nothing applied")
     |> push_navigate(to: ~p"/training")}
  end

  @impl true
  def handle_info({:training_workout, %Training.Workout{} = workout}, socket) do
    if workout.status == :active do
      {:noreply, reload(socket)}
    else
      {:noreply, push_navigate(socket, to: ~p"/training")}
    end
  end

  def handle_info({:training_workout, %WorkoutSet{}}, socket) do
    {:noreply, reload(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp reload(socket) do
    case Training.active_workout(socket.assigns.current_user) do
      nil -> push_navigate(socket, to: ~p"/training")
      workout -> assign(socket, :workout, workout)
    end
  end

  defp rest_ends_at(socket, set) do
    seconds = set.exercise.rest_seconds || socket.assigns.settings.default_rest_seconds
    DateTime.add(DateTime.utc_now(), seconds, :second)
  end

  # ---- view helpers ----------------------------------------------------

  # Sets in position order, chunked into contiguous exercise blocks.
  defp exercise_blocks(workout) do
    workout.sets
    |> Enum.sort_by(& &1.position)
    |> Enum.chunk_by(& &1.exercise_id)
  end

  defp block_title([set | _] = sets) do
    weight =
      case set.prescribed_weight_kg do
        nil -> ""
        weight -> " @ #{weight |> Decimal.normalize() |> Decimal.to_string(:normal)} kg"
      end

    "#{set.exercise_name} — #{length(sets)}×#{set.target_reps}#{weight}"
  end

  defp done_count(workout), do: Enum.count(workout.sets, & &1.completed_at)

  defp resting?(nil), do: false
  defp resting?(ends_at), do: DateTime.compare(ends_at, DateTime.utc_now()) == :gt

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between gap-3">
        <div>
          <h1 class="font-display text-2xl font-bold tracking-tight text-accent">
            Session {@workout.template_name}
          </h1>
          <p class="text-sm text-neutral-content/70">
            {done_count(@workout)}/{length(@workout.sets)} sets
          </p>
        </div>
        <div
          :if={resting?(@rest_ends_at)}
          class="text-center bg-base-200 border border-base-300 rounded-box px-4 py-2"
        >
          <p class="text-xs text-neutral-content/60">Rest</p>
          <p
            class="font-mono text-xl tabular-nums"
            id={"rest-countdown-#{DateTime.to_unix(@rest_ends_at)}"}
            phx-hook="FocusCountdown"
            data-ends-at={DateTime.to_iso8601(@rest_ends_at)}
          >
            --:--
          </p>
        </div>
      </div>

      <div :for={sets <- exercise_blocks(@workout)} class="card bg-base-200 border border-base-300">
        <div class="card-body p-4 space-y-2">
          <div class="flex items-center gap-2">
            <h2 class="font-medium flex-1">{block_title(sets)}</h2>
            <span :if={hd(sets).slot_kind == :accessory} class="badge badge-ghost badge-sm">
              accessory
            </span>
          </div>
          <div class="flex gap-2 flex-wrap">
            <div :for={set <- sets} class="flex flex-col items-center gap-1">
              <button
                phx-click="toggle_set"
                phx-value-id={set.id}
                class={[
                  "btn btn-circle text-base",
                  set.completed_at && "btn-primary",
                  !set.completed_at && "btn-outline border-base-300"
                ]}
              >
                {set.actual_reps || set.target_reps}
              </button>
              <button
                :if={set.completed_at}
                phx-click="decrement_set"
                phx-value-id={set.id}
                class="btn btn-ghost btn-xs"
                title="One rep fewer"
              >
                −
              </button>
              <span :if={!set.completed_at} class="h-6"></span>
            </div>
          </div>
        </div>
      </div>

      <div class="flex gap-2 justify-end">
        <button
          phx-click="abandon"
          data-confirm="Abandon this workout? Nothing will be applied."
          class="btn btn-ghost text-error"
        >
          Abandon
        </button>
        <button
          phx-click="finish"
          data-confirm={
            if done_count(@workout) < length(@workout.sets),
              do: "Some sets are unlogged — they'll count as misses. Finish anyway?"
          }
          class="btn btn-primary"
        >
          <.icon name="hero-flag-micro" class="size-4" /> Finish workout
        </button>
      </div>
    </Layouts.app>
    """
  end
end
