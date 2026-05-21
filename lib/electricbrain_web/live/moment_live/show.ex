defmodule ElectricbrainWeb.MomentLive.Show do
  use ElectricbrainWeb, :live_view

  alias Electricbrain.Moments.Moment

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    moment = Ash.get!(Moment, id, actor: user)
    categories = Electricbrain.Categories.list_with_paths(user)
    by_id = Map.new(categories, &{&1.id, &1})

    {:ok,
     socket
     |> assign(:page_title, moment.name)
     |> assign(:moment, moment)
     |> assign(:category, Map.get(by_id, moment.category_id))}
  end

  defp kind_label(:craving), do: "Craving"
  defp kind_label(:urge), do: "Urge"
  defp kind_label(:feeling), do: "Feeling"
  defp kind_label(:other), do: "Other"

  defp kind_color(:craving), do: "badge-warning"
  defp kind_color(:urge), do: "badge-accent"
  defp kind_color(:feeling), do: "badge-info"
  defp kind_color(:other), do: "badge-ghost"

  defp format_local(dt, tz) do
    dt |> DateTime.shift_zone!(tz || "Etc/UTC") |> Calendar.strftime("%A, %d %b %Y · %H:%M")
  end

  attr :letter, :string, required: true
  attr :word, :string, required: true
  attr :hint, :string, required: true
  attr :text, :any, required: true

  defp rain_block(assigns) do
    ~H"""
    <div :if={@text && @text != ""} class="space-y-1">
      <div class="flex items-baseline gap-2">
        <span class="font-display text-lg font-bold text-accent">{@letter}</span>
        <span class="font-medium">{@word}</span>
        <span class="text-xs text-neutral-content/60">— {@hint}</span>
      </div>
      <p class="text-sm whitespace-pre-wrap text-neutral-content/90 pl-6">{@text}</p>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} now_agenda={assigns[:now_agenda]}>
      <div class="max-w-xl mx-auto space-y-4">
        <div>
          <.link navigate={~p"/moments"} class="text-xs text-neutral-content/60 hover:underline">
            ← Moments
          </.link>
          <div class="flex items-baseline gap-3 mt-1 flex-wrap">
            <h1 class="font-display text-3xl font-bold tracking-tight text-accent drop-shadow-[0_0_12px_var(--color-accent)]">
              {@moment.name}
            </h1>
            <span class={["badge", kind_color(@moment.kind)]}>
              {kind_label(@moment.kind)}
            </span>
          </div>
          <p class="text-sm text-neutral-content/70">
            {format_local(@moment.inserted_at, @current_user.timezone)} · intensity {@moment.intensity}/5
            <%= if @category do %>
              · {ElectricbrainWeb.CategoryPicker.breadcrumb(@category.path)}
            <% end %>
          </p>
        </div>

        <div class="card bg-base-200 border border-base-300">
          <div class="card-body p-4 space-y-4">
            <.rain_block letter="R" word="Recognize" hint="What's here?" text={@moment.recognize} />
            <.rain_block letter="A" word="Allow" hint="Can I let it be?" text={@moment.allow} />
            <.rain_block
              letter="I"
              word="Investigate"
              hint="What does it want?"
              text={@moment.investigate}
            />
            <.rain_block
              letter="N"
              word="Nurture"
              hint="What does this part of me need?"
              text={@moment.nurture}
            />

            <%= if Enum.all?([@moment.recognize, @moment.allow, @moment.investigate, @moment.nurture], &(&1 in [nil, ""])) do %>
              <p class="text-sm text-neutral-content/60">
                You sat with it without journalling — that's still a pause.
              </p>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
