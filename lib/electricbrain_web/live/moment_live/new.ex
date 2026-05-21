defmodule ElectricbrainWeb.MomentLive.New do
  use ElectricbrainWeb, :live_view

  alias Electricbrain.Moments.Moment
  alias ElectricbrainWeb.CategoryPicker

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Pause")
     |> CategoryPicker.assign(user)
     |> CategoryPicker.attach()
     |> assign(:form, new_form(user))
     |> assign(:kind, :craving)}
  end

  defp new_form(user) do
    Moment
    |> AshPhoenix.Form.for_create(:create,
      actor: user,
      params: %{"kind" => "craving", "intensity" => "3"}
    )
    |> to_form()
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("pick_kind", %{"kind" => kind}, socket) do
    {:noreply, assign(socket, :kind, String.to_existing_atom(kind))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    params =
      params
      |> Map.put("category_id", socket.assigns.picker_selected_id)
      |> Map.put("kind", Atom.to_string(socket.assigns.kind))

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _moment} ->
        {:noreply,
         socket
         |> put_flash(:info, "You sat with it. The moment is recorded.")
         |> push_navigate(to: ~p"/moments")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  defp kind_label(:craving), do: "Craving"
  defp kind_label(:urge), do: "Urge"
  defp kind_label(:feeling), do: "Feeling"
  defp kind_label(:other), do: "Other"

  attr :kind, :atom, required: true
  attr :selected, :atom, required: true

  defp kind_chip(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="pick_kind"
      phx-value-kind={Atom.to_string(@kind)}
      class={[
        "btn btn-sm",
        if(@kind == @selected, do: "btn-primary", else: "btn-outline")
      ]}
    >
      {kind_label(@kind)}
    </button>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      now_agenda={assigns[:now_agenda]}
      show_pause_fab={false}
    >
      <div class="max-w-xl mx-auto space-y-4">
        <div>
          <.link navigate={~p"/moments"} class="text-xs text-neutral-content/60 hover:underline">
            ← Moments
          </.link>
          <h1 class="font-display text-3xl font-bold tracking-tight text-accent">
            Pause
          </h1>
          <p class="text-sm text-neutral-content/70">
            Sit with what's here. Name it. Let it move through.
          </p>
        </div>

        <.form
          for={@form}
          id="moment-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <div class="card bg-base-200 border border-base-300">
            <div class="card-body p-4 space-y-3">
              <div>
                <label class="label"><span class="label-text text-xs">Kind</span></label>
                <div class="flex flex-wrap gap-2">
                  <.kind_chip kind={:craving} selected={@kind} />
                  <.kind_chip kind={:urge} selected={@kind} />
                  <.kind_chip kind={:feeling} selected={@kind} />
                  <.kind_chip kind={:other} selected={@kind} />
                </div>
              </div>

              <div>
                <label class="label">
                  <span class="label-text text-xs">What is it?</span>
                </label>
                <input
                  type="text"
                  name={@form[:name].name}
                  value={Phoenix.HTML.Form.normalize_value("text", @form[:name].value)}
                  class="input input-bordered input-lg w-full bg-base-100"
                  placeholder="chocolate, a beer, the boss email…"
                  required
                  autocomplete="off"
                  inputmode="text"
                  autofocus
                />
              </div>

              <div>
                <label class="label">
                  <span class="label-text text-xs">Intensity</span>
                  <span class="label-text-alt font-mono">
                    {@form[:intensity].value || 3} / 5
                  </span>
                </label>
                <input
                  type="range"
                  name={@form[:intensity].name}
                  value={@form[:intensity].value || 3}
                  min="1"
                  max="5"
                  step="1"
                  class="range range-accent w-full"
                />
              </div>

              <div>
                <label class="label"><span class="label-text text-xs">Category</span></label>
                <CategoryPicker.picker
                  categories={@categories}
                  categories_by_id={@categories_by_id}
                  selected_id={@picker_selected_id}
                  query={@picker_query}
                  open={@picker_open}
                />
              </div>
            </div>
          </div>

          <div class="card bg-base-200 border border-base-300">
            <div class="card-body p-4 space-y-3">
              <h2 class="card-title text-base">RAIN</h2>
              <p class="text-xs text-neutral-content/60">
                Skip any prompt you don't need right now. The point is sitting with it, not filling boxes.
              </p>

              <div>
                <label class="label">
                  <span class="label-text"><strong>R</strong>ecognize</span>
                  <span class="label-text-alt text-neutral-content/60">What's here?</span>
                </label>
                <textarea
                  name={@form[:recognize].name}
                  rows="2"
                  class="textarea textarea-bordered w-full bg-base-100"
                  placeholder="A tightness in my chest. A pull toward the fridge."
                ><%= Phoenix.HTML.Form.normalize_value("textarea", @form[:recognize].value) %></textarea>
              </div>

              <div>
                <label class="label">
                  <span class="label-text"><strong>A</strong>llow</span>
                  <span class="label-text-alt text-neutral-content/60">Can I let it be?</span>
                </label>
                <textarea
                  name={@form[:allow].name}
                  rows="2"
                  class="textarea textarea-bordered w-full bg-base-100"
                  placeholder="Yes. It's allowed to be here without my fixing it."
                ><%= Phoenix.HTML.Form.normalize_value("textarea", @form[:allow].value) %></textarea>
              </div>

              <div>
                <label class="label">
                  <span class="label-text"><strong>I</strong>nvestigate</span>
                  <span class="label-text-alt text-neutral-content/60">
                    What does it want? Where in the body?
                  </span>
                </label>
                <textarea
                  name={@form[:investigate].name}
                  rows="2"
                  class="textarea textarea-bordered w-full bg-base-100"
                  placeholder="Behind my eyes. It wants comfort. It wants the day to be over."
                ><%= Phoenix.HTML.Form.normalize_value("textarea", @form[:investigate].value) %></textarea>
              </div>

              <div>
                <label class="label">
                  <span class="label-text"><strong>N</strong>urture</span>
                  <span class="label-text-alt text-neutral-content/60">
                    What does this part of me need?
                  </span>
                </label>
                <textarea
                  name={@form[:nurture].name}
                  rows="2"
                  class="textarea textarea-bordered w-full bg-base-100"
                  placeholder="A long breath. To know it's OK to be tired."
                ><%= Phoenix.HTML.Form.normalize_value("textarea", @form[:nurture].value) %></textarea>
              </div>
            </div>
          </div>

          <div class="flex justify-end gap-2">
            <.link navigate={~p"/moments"} class="btn btn-ghost">Cancel</.link>
            <button type="submit" class="btn btn-primary btn-lg">Save</button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
