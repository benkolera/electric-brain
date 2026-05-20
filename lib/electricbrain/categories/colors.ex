defmodule Electricbrain.Categories.Colors do
  @moduledoc """
  Google Calendar's fixed 11-color event palette, mirrored so the planner
  UI and the Google Calendar view show the same color for an entry.

  Each `color_id` (1–11) is the value Google accepts in the event's
  `colorId` field; the matching hex is what Google's UI renders that
  color as (sourced from Google Calendar API docs). Using the same id
  means there's no nearest-color matching and the two views never
  drift.

  Categories form a tree; a nil `color_id` inherits from the parent,
  falling back to `default_id/0` (Graphite, neutral grey) at the root.
  """

  @palette %{
    1 => %{name: "Lavender", hex: "#7986cb"},
    2 => %{name: "Sage", hex: "#33b679"},
    3 => %{name: "Grape", hex: "#8e24aa"},
    4 => %{name: "Flamingo", hex: "#e67c73"},
    5 => %{name: "Banana", hex: "#f6c026"},
    6 => %{name: "Tangerine", hex: "#f5511d"},
    7 => %{name: "Peacock", hex: "#039be5"},
    8 => %{name: "Graphite", hex: "#616161"},
    9 => %{name: "Blueberry", hex: "#3f51b5"},
    10 => %{name: "Basil", hex: "#0b8043"},
    11 => %{name: "Tomato", hex: "#d60000"}
  }

  @default_id 8

  @doc "The full id→%{name, hex} map, for swatch pickers and previews."
  def palette, do: @palette

  @doc "Color id used when nothing is set anywhere up the parent chain."
  def default_id, do: @default_id

  def default_hex, do: @palette[@default_id].hex

  def hex_for(nil), do: default_hex()

  def hex_for(id) when is_integer(id) do
    case Map.get(@palette, id) do
      %{hex: hex} -> hex
      _ -> default_hex()
    end
  end

  def name_for(nil), do: @palette[@default_id].name

  def name_for(id) when is_integer(id) do
    case Map.get(@palette, id) do
      %{name: name} -> name
      _ -> "Unknown"
    end
  end

  @doc """
  Walks the parent chain in `categories_by_id` to find an effective
  `color_id`, falling back to `default_id/0` if nothing is set anywhere
  up the tree (or the category id isn't in the map). Cycle-safe via a
  visited set, though Categories enforces tree shape.
  """
  def resolve_id(_categories_by_id, nil), do: @default_id

  def resolve_id(categories_by_id, category_id) when is_map(categories_by_id) do
    walk(categories_by_id, category_id, MapSet.new())
  end

  defp walk(_map, nil, _seen), do: @default_id

  defp walk(map, id, seen) do
    if MapSet.member?(seen, id) do
      @default_id
    else
      case Map.get(map, id) do
        nil -> @default_id
        %{color_id: cid} when is_integer(cid) -> cid
        %{parent_id: parent_id} -> walk(map, parent_id, MapSet.put(seen, id))
        _ -> @default_id
      end
    end
  end
end
