defmodule ElectricbrainWeb.HabitLive.FormFields do
  @moduledoc """
  Shared Habit form fields used by the create modal on the index page and the
  edit page. Conditionally hides count fields (min_count / period /
  duration_minutes) when the habit is in fixed-schedule mode — those fields
  don't apply because the entry length comes from the availability window.
  """
  use Phoenix.Component
  import ElectricbrainWeb.CoreComponents, only: [icon: 1]
  alias ElectricbrainWeb.CategoryPicker

  attr :form, :map, required: true
  attr :categories, :list, required: true
  attr :categories_by_id, :map, required: true
  attr :picker_selected_id, :string, required: true
  attr :picker_query, :string, required: true
  attr :picker_open, :boolean, required: true

  def habit_form_fields(assigns) do
    ~H"""
    <div class="grid sm:grid-cols-2 gap-3">
      <div class="sm:col-span-2">
        <label class="label">
          <span class="label-text text-xs">Title</span>
        </label>
        <input
          type="text"
          name={@form[:title].name}
          value={Phoenix.HTML.Form.normalize_value("text", @form[:title].value)}
          class="input input-bordered w-full bg-base-100"
          placeholder="Exercise, meditate, read…"
          autocomplete="off"
          required
        />
      </div>

      <div class="sm:col-span-2">
        <label class="label">
          <span class="label-text text-xs">Category</span>
        </label>
        <CategoryPicker.picker
          categories={@categories}
          categories_by_id={@categories_by_id}
          selected_id={@picker_selected_id}
          query={@picker_query}
          open={@picker_open}
        />
      </div>

      <div class="sm:col-span-2">
        <label class="cursor-pointer label gap-2 px-3 py-2 border border-base-300 rounded-lg bg-base-100 inline-flex">
          <input type="hidden" name={@form[:fixed_schedule].name} value="false" />
          <input
            type="checkbox"
            name={@form[:fixed_schedule].name}
            value="true"
            checked={truthy?(@form[:fixed_schedule].value)}
            class="checkbox checkbox-sm checkbox-primary"
          />
          <span class="label-text text-xs">
            <.icon name="hero-bolt-micro" class="size-3 inline" />
            Fixed schedule — auto-place once per availability window
          </span>
        </label>
      </div>

      <%= unless truthy?(@form[:fixed_schedule].value) do %>
        <div>
          <label class="label">
            <span class="label-text text-xs">Min count</span>
          </label>
          <input
            type="number"
            name={@form[:min_count].name}
            value={Phoenix.HTML.Form.normalize_value("number", @form[:min_count].value) || 1}
            min="1"
            class="input input-bordered w-full bg-base-100"
          />
        </div>

        <div>
          <label class="label">
            <span class="label-text text-xs">Period</span>
          </label>
          <select name={@form[:period].name} class="select select-bordered bg-base-100 w-full">
            <option value="day" selected={@form[:period].value in [:day, "day"]}>per day</option>
            <option value="week" selected={@form[:period].value in [nil, :week, "week"]}>
              per week
            </option>
            <option value="month" selected={@form[:period].value in [:month, "month"]}>
              per month
            </option>
          </select>
        </div>

        <div class="sm:col-span-2">
          <label class="label">
            <span class="label-text text-xs">Duration (min)</span>
          </label>
          <input
            type="number"
            name={@form[:duration_minutes].name}
            value={Phoenix.HTML.Form.normalize_value("number", @form[:duration_minutes].value)}
            min="0"
            class="input input-bordered w-full bg-base-100"
            placeholder="Optional — leave blank for tasks without a fixed length"
          />
        </div>

        <div class="sm:col-span-2">
          <label class="label">
            <span class="label-text text-xs">Identity</span>
            <span class="label-text-alt text-neutral-content/50">Doing this means you are…</span>
          </label>
          <input
            type="text"
            name={@form[:identity_statement].name}
            value={
              Phoenix.HTML.Form.normalize_value("text", @form[:identity_statement].value)
            }
            class="input input-bordered w-full bg-base-100"
            placeholder="…someone who writes every day"
            autocomplete="off"
          />
        </div>

        <div class="sm:col-span-2">
          <label class="label">
            <span class="label-text text-xs">Minimum viable action</span>
            <span class="label-text-alt text-neutral-content/50">
              Two-minute fallback when energy is low
            </span>
          </label>
          <input
            type="text"
            name={@form[:minimum_viable_action].name}
            value={
              Phoenix.HTML.Form.normalize_value("text", @form[:minimum_viable_action].value)
            }
            class="input input-bordered w-full bg-base-100"
            placeholder="Write one sentence"
            autocomplete="off"
          />
        </div>
      <% end %>

      <div>
        <label class="label">
          <span class="label-text text-xs">Buffer before (min)</span>
        </label>
        <input
          type="number"
          name={@form[:buffer_before_minutes].name}
          value={
            Phoenix.HTML.Form.normalize_value("number", @form[:buffer_before_minutes].value) || 0
          }
          min="0"
          class="input input-bordered w-full bg-base-100"
        />
      </div>

      <div>
        <label class="label">
          <span class="label-text text-xs">Buffer after (min)</span>
        </label>
        <input
          type="number"
          name={@form[:buffer_after_minutes].name}
          value={
            Phoenix.HTML.Form.normalize_value("number", @form[:buffer_after_minutes].value) || 0
          }
          min="0"
          class="input input-bordered w-full bg-base-100"
        />
      </div>
    </div>
    """
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false
end
