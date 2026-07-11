defmodule ElectricbrainWeb.MealLive.Settings do
  @moduledoc """
  Nutrition profile form + computed targets panel. The panel shows the
  Mifflin-St Jeor chain (BMR → TDEE → goal target → macro split) from
  the saved profile and the latest weight measurement, plus last
  week's weight change as feedback. Overrides are nil-means-computed.
  """

  use ElectricbrainWeb, :live_view

  require Ash.Query

  alias Electricbrain.Meals
  alias Electricbrain.Meals.NutritionProfile
  alias Electricbrain.Meals.Targets
  alias Electricbrain.Meals.Weight
  alias Electricbrain.Metrics.Metric

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Meal settings")
     |> assign(:metrics, list_metrics(user))
     |> load_profile()}
  end

  defp load_profile(socket) do
    user = socket.assigns.current_user
    profile = Meals.profile_for(user)

    linked_ids =
      if profile do
        Meals.feedback_metrics(user, profile) |> Enum.map(& &1.metric_id) |> MapSet.new()
      else
        MapSet.new()
      end

    socket
    |> assign(:profile, profile)
    |> assign(:form, profile_form(user, profile))
    |> assign(:linked_metric_ids, linked_ids)
    |> assign_panel(profile)
  end

  defp profile_form(user, nil) do
    NutritionProfile
    |> AshPhoenix.Form.for_create(:create, actor: user)
    |> to_form()
  end

  defp profile_form(user, profile) do
    profile
    |> AshPhoenix.Form.for_update(:update, actor: user)
    |> to_form()
  end

  defp list_metrics(user) do
    Metric
    |> Ash.Query.sort(name: :asc)
    |> Ash.read!(actor: user)
  end

  defp assign_panel(socket, nil) do
    socket
    |> assign(:weight, :none)
    |> assign(:week_delta, :none)
    |> assign(:computed, nil)
    |> assign(:resolved, nil)
  end

  defp assign_panel(socket, profile) do
    user = socket.assigns.current_user
    weight = Weight.latest(user, profile)
    week_delta = Weight.week_delta(user, profile)
    today = user.timezone |> DateTime.now!() |> DateTime.to_date()

    computed =
      case weight do
        {:ok, %{kg: kg}} ->
          case Targets.compute(profile, Decimal.to_float(kg), today) do
            {:ok, computed} -> computed
            {:error, :incomplete_profile} -> nil
          end

        :none ->
          nil
      end

    resolved =
      case Targets.resolve(profile, computed) do
        {:ok, resolved} -> resolved
        {:error, :incomplete_targets} -> nil
      end

    socket
    |> assign(:weight, weight)
    |> assign(:week_delta, week_delta)
    |> assign(:computed, computed)
    |> assign(:resolved, resolved)
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    params = normalise_blank_overrides(params)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _profile} ->
        {:noreply,
         socket
         |> put_flash(:info, "Meal settings saved")
         |> load_profile()}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("save_progress_metrics", params, socket) do
    user = socket.assigns.current_user
    metric_ids = Map.get(params, "metric_ids", [])

    :ok = Meals.set_feedback_metrics(user, socket.assigns.profile, metric_ids)

    {:noreply,
     socket
     |> put_flash(:info, "Progress metrics saved")
     |> load_profile()}
  end

  # Blank override inputs mean "computed" — nil, not a cast error.
  defp normalise_blank_overrides(params) do
    Enum.reduce(
      ~w(override_kcal override_protein_g override_fat_g override_carbs_g height_cm birthdate sex weight_metric_id),
      params,
      fn key, acc ->
        case acc[key] do
          "" -> Map.put(acc, key, nil)
          _ -> acc
        end
      end
    )
  end

  defp fmt_delta(decimal) do
    str = decimal |> Decimal.round(2) |> Decimal.normalize() |> Decimal.to_string(:normal)
    if Decimal.compare(decimal, 0) == :gt, do: "+" <> str, else: str
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 class="font-display text-3xl font-bold tracking-tight text-accent">
            Meal settings
          </h1>
          <p class="text-sm text-neutral-content/70">
            Body inputs, goal, and macro split — the weekly meal plan targets come from here.
          </p>
        </div>
        <.link navigate={~p"/settings"} class="btn btn-ghost btn-sm">App settings</.link>
      </div>

      <div class="card bg-base-200 border border-base-300">
        <div class="card-body">
          <h2 class="card-title">Current targets</h2>
          <%= if @profile == nil do %>
            <p class="text-sm text-neutral-content/60">
              Save your profile below and targets will appear here.
            </p>
          <% else %>
            <div class="text-sm space-y-1">
              <p :if={@weight != :none}>
                <% {:ok, w} = @weight %> Based on
                <span class="font-medium">
                  {w.kg |> Decimal.round(1) |> Decimal.to_string(:normal)} kg
                </span>
                measured {Calendar.strftime(w.recorded_at, "%d %b")}.
                <span :if={@week_delta != :none}>
                  <% {:ok, delta} = @week_delta %> Last week: <span class="font-medium">{fmt_delta(delta)} kg</span>.
                </span>
              </p>
              <p :if={@weight == :none} class="text-neutral-content/60">
                No weight readings yet — link a weight metric below and log a measurement,
                or set a manual calorie override.
              </p>
              <p :if={@computed}>
                BMR <span class="font-medium">{@computed.bmr}</span> kcal ·
                TDEE <span class="font-medium">{@computed.tdee}</span> kcal ·
                goal target <span class="font-medium">{@computed.kcal}</span> kcal
              </p>
              <%= if @resolved do %>
                <p class="text-base">
                  <span class="font-medium">{@resolved.kcal} kcal</span>
                  · P <span class="font-medium">{@resolved.protein_g}g</span>
                  · F <span class="font-medium">{@resolved.fat_g}g</span>
                  · C <span class="font-medium">{@resolved.carbs_g}g</span>
                  <span class="text-xs text-neutral-content/60">daily, overrides applied</span>
                </p>
              <% else %>
                <p class="text-warning text-sm">
                  Targets incomplete — fill in height / birthdate / sex and log a weight,
                  or set all four overrides.
                </p>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <.form
        for={@form}
        id="nutrition-profile-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <div class="card bg-base-200 border border-base-300">
          <div class="card-body space-y-3">
            <h2 class="card-title">Body & goal</h2>
            <div class="grid sm:grid-cols-3 gap-3">
              <div>
                <label class="label"><span class="label-text text-xs">Height (cm)</span></label>
                <input
                  type="number"
                  step="any"
                  name={@form[:height_cm].name}
                  value={Phoenix.HTML.Form.normalize_value("number", @form[:height_cm].value)}
                  class="input input-bordered w-full bg-base-100"
                  autocomplete="off"
                />
              </div>

              <div>
                <label class="label"><span class="label-text text-xs">Birthdate</span></label>
                <input
                  type="date"
                  name={@form[:birthdate].name}
                  value={Phoenix.HTML.Form.normalize_value("date", @form[:birthdate].value)}
                  class="input input-bordered w-full bg-base-100"
                />
              </div>

              <div>
                <label class="label"><span class="label-text text-xs">Sex (for BMR)</span></label>
                <select name={@form[:sex].name} class="select select-bordered bg-base-100 w-full">
                  <option value="" selected={@form[:sex].value in [nil, ""]}>(not set)</option>
                  <option value="male" selected={@form[:sex].value in [:male, "male"]}>Male</option>
                  <option value="female" selected={@form[:sex].value in [:female, "female"]}>
                    Female
                  </option>
                </select>
              </div>

              <div>
                <label class="label"><span class="label-text text-xs">Activity level</span></label>
                <select
                  name={@form[:activity_level].name}
                  class="select select-bordered bg-base-100 w-full"
                >
                  <option
                    :for={
                      {value, label} <- [
                        {"sedentary", "Sedentary (desk, no training)"},
                        {"light", "Light (1–3 sessions/week)"},
                        {"moderate", "Moderate (3–5 sessions/week)"},
                        {"active", "Active (6–7 sessions/week)"},
                        {"very_active", "Very active (physical job + training)"}
                      ]
                    }
                    value={value}
                    selected={to_string(@form[:activity_level].value || "light") == value}
                  >
                    {label}
                  </option>
                </select>
              </div>

              <div>
                <label class="label"><span class="label-text text-xs">Goal</span></label>
                <select name={@form[:goal].name} class="select select-bordered bg-base-100 w-full">
                  <option
                    :for={
                      {value, label} <- [
                        {"cut", "Cut (deficit)"},
                        {"maintain", "Maintain"},
                        {"bulk", "Bulk (surplus)"}
                      ]
                    }
                    value={value}
                    selected={to_string(@form[:goal].value || "maintain") == value}
                  >
                    {label}
                  </option>
                </select>
              </div>

              <div>
                <label class="label">
                  <span class="label-text text-xs">Rate (kcal/day above/below TDEE)</span>
                </label>
                <input
                  type="number"
                  step="50"
                  min="0"
                  name={@form[:goal_rate_kcal_per_day].name}
                  value={
                    Phoenix.HTML.Form.normalize_value(
                      "number",
                      @form[:goal_rate_kcal_per_day].value
                    ) || 400
                  }
                  class="input input-bordered w-full bg-base-100"
                  autocomplete="off"
                />
              </div>

              <div class="sm:col-span-3">
                <label class="label"><span class="label-text text-xs">Weight metric</span></label>
                <select
                  name={@form[:weight_metric_id].name}
                  class="select select-bordered bg-base-100 w-full"
                >
                  <option value="" selected={@form[:weight_metric_id].value in [nil, ""]}>
                    (none — set a manual calorie override instead)
                  </option>
                  <option
                    :for={metric <- @metrics}
                    value={metric.id}
                    selected={to_string(@form[:weight_metric_id].value) == metric.id}
                  >
                    {metric.name} ({metric.unit})
                  </option>
                </select>
                <p class="text-xs text-neutral-content/50 mt-1">
                  Your weight series in Metrics — the latest reading feeds BMR, and week-over-week
                  change shows whether the plan is working.
                </p>
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-200 border border-base-300">
          <div class="card-body space-y-3">
            <h2 class="card-title">Macro split & overrides</h2>
            <div class="grid sm:grid-cols-2 gap-3">
              <div>
                <label class="label">
                  <span class="label-text text-xs">Protein (g per kg bodyweight)</span>
                </label>
                <input
                  type="number"
                  step="0.1"
                  min="0.5"
                  name={@form[:protein_g_per_kg].name}
                  value={
                    Phoenix.HTML.Form.normalize_value("number", @form[:protein_g_per_kg].value) ||
                      "2.0"
                  }
                  class="input input-bordered w-full bg-base-100"
                  autocomplete="off"
                />
              </div>

              <div>
                <label class="label">
                  <span class="label-text text-xs">Fat (% of calories; carbs get the rest)</span>
                </label>
                <input
                  type="number"
                  step="1"
                  min="10"
                  max="60"
                  name={@form[:fat_pct].name}
                  value={Phoenix.HTML.Form.normalize_value("number", @form[:fat_pct].value) || 25}
                  class="input input-bordered w-full bg-base-100"
                  autocomplete="off"
                />
              </div>

              <.override_input form={@form} field={:override_kcal} label="Calories override (kcal)" />
              <.override_input
                form={@form}
                field={:override_protein_g}
                label="Protein override (g)"
              />
              <.override_input form={@form} field={:override_fat_g} label="Fat override (g)" />
              <.override_input form={@form} field={:override_carbs_g} label="Carbs override (g)" />
            </div>
            <p class="text-xs text-neutral-content/50">
              Leave overrides blank to use the computed values. A filled override wins for that
              field only.
            </p>
          </div>
        </div>

        <div class="card bg-base-200 border border-base-300">
          <div class="card-body space-y-3">
            <h2 class="card-title">Meal times & reminders</h2>
            <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <.time_input form={@form} field={:breakfast_time} label="Breakfast" />
              <.time_input form={@form} field={:shake_time} label="Shake" />
              <.time_input form={@form} field={:lunch_time} label="Lunch" />
              <.time_input form={@form} field={:snack_time} label="Snack" />
              <.time_input form={@form} field={:dinner_time} label="Dinner" />
              <.time_input form={@form} field={:shopping_reminder_time} label="Shopping (Sat)" />
              <.time_input form={@form} field={:prep_reminder_time} label="Meal prep (Sun)" />

              <div>
                <label class="label"><span class="label-text text-xs">Max shakes/day</span></label>
                <input
                  type="number"
                  step="1"
                  min="0"
                  max="5"
                  name={@form[:max_shakes_per_day].name}
                  value={
                    Phoenix.HTML.Form.normalize_value("number", @form[:max_shakes_per_day].value) ||
                      2
                  }
                  class="input input-bordered w-full bg-base-100"
                  autocomplete="off"
                />
              </div>
            </div>
          </div>
        </div>

        <div class="flex justify-end">
          <button type="submit" class="btn btn-primary">Save meal settings</button>
        </div>
      </.form>

      <form
        :if={@profile}
        phx-submit="save_progress_metrics"
        class="card bg-base-200 border border-base-300"
      >
        <div class="card-body space-y-3">
          <h2 class="card-title">Progress metrics</h2>
          <p class="text-sm text-neutral-content/70">
            Pick the metrics that tell you whether the plan is working — weight, waist,
            body fat %, key lifts. Their weekly trend shows on the meal plan page.
          </p>
          <%= if @metrics == [] do %>
            <p class="text-sm text-neutral-content/50">
              No metrics yet — create them on the
              <.link navigate={~p"/metrics"} class="underline">Metrics</.link>
              page first.
            </p>
          <% else %>
            <div class="grid sm:grid-cols-2 gap-1">
              <label :for={metric <- @metrics} class="flex items-center gap-2 py-1 cursor-pointer">
                <input
                  type="checkbox"
                  name="metric_ids[]"
                  value={metric.id}
                  checked={MapSet.member?(@linked_metric_ids, metric.id)}
                  class="checkbox checkbox-sm checkbox-primary"
                />
                <span class="text-sm">{metric.name} ({metric.unit})</span>
              </label>
            </div>
            <div class="flex justify-end">
              <button type="submit" class="btn btn-primary btn-sm">Save progress metrics</button>
            </div>
          <% end %>
        </div>
      </form>
    </Layouts.app>
    """
  end

  attr :form, :map, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true

  defp override_input(assigns) do
    ~H"""
    <div>
      <label class="label"><span class="label-text text-xs">{@label}</span></label>
      <input
        type="number"
        step="1"
        min="0"
        name={@form[@field].name}
        value={Phoenix.HTML.Form.normalize_value("number", @form[@field].value)}
        placeholder="computed"
        class="input input-bordered w-full bg-base-100"
        autocomplete="off"
      />
    </div>
    """
  end

  attr :form, :map, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true

  defp time_input(assigns) do
    ~H"""
    <div>
      <label class="label"><span class="label-text text-xs">{@label}</span></label>
      <input
        type="time"
        name={@form[@field].name}
        value={time_value(@form[@field].value)}
        class="input input-bordered w-full bg-base-100"
      />
    </div>
    """
  end

  defp time_value(%Time{} = t),
    do: t |> Time.truncate(:second) |> Time.to_string() |> String.slice(0, 5)

  defp time_value(value) when is_binary(value), do: value
  defp time_value(_), do: nil
end
