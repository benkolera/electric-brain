defmodule Electricbrain.Planner.EntryTarget do
  @moduledoc """
  Polymorphism helpers for `Planner.Entry`.

  An entry points at exactly one of a `Todo`, `Habit`, or `TimeBlock` (DB
  check constraint). Every consumer that asks "what is this entry actually?"
  used to redo the same cond/pattern-match across all three branches in its
  own module. This module is the single dispatch site — add a fourth target
  kind and the impact is one file, not ten.

  Most functions expect the target relationship (`:todo` / `:habit` /
  `:time_block`) to be loaded on the entry. `recurring?/1` additionally
  needs `entry.todo.recurrence` (i.e. the todo loaded).
  """

  @type kind :: :todo | :habit | :time_block | nil

  @doc "Returns the underlying schedulable struct, or nil if none loaded."
  def schedulable(entry) when is_map(entry) do
    loaded(Map.get(entry, :todo)) ||
      loaded(Map.get(entry, :habit)) ||
      loaded(Map.get(entry, :time_block))
  end

  def schedulable(_), do: nil

  defp loaded(%Ash.NotLoaded{}), do: nil
  defp loaded(other), do: other

  @doc "Returns the kind atom based on which FK column is populated."
  @spec kind(map()) :: kind()
  def kind(%{todo_id: id}) when not is_nil(id), do: :todo
  def kind(%{habit_id: id}) when not is_nil(id), do: :habit
  def kind(%{time_block_id: id}) when not is_nil(id), do: :time_block
  def kind(_), do: nil

  @doc ~s(String form of `kind/1` — e.g. "todo" — for badge labels.)
  def kind_label(entry), do: entry |> kind() |> to_string()

  @doc "Title of the schedulable, with a stable fallback."
  def title(entry) do
    case schedulable(entry) do
      %{title: t} when is_binary(t) -> t
      _ -> "(untitled)"
    end
  end

  @doc "Category id of the schedulable, or nil."
  def category_id(entry) do
    case schedulable(entry) do
      %{category_id: cid} -> cid
      _ -> nil
    end
  end

  @doc """
  Resolved duration for the entry: per-entry override beats schedulable
  default beats the global 60-minute fallback. This is the canonical chain;
  reading the schedulable's `duration_minutes` directly is a bug (fixed
  time-blocks override per-entry from the availability window length).
  """
  def duration_minutes(entry) do
    cond do
      is_integer(entry.duration_minutes) ->
        entry.duration_minutes

      match?(%{duration_minutes: d} when is_integer(d), schedulable(entry)) ->
        schedulable(entry).duration_minutes

      true ->
        60
    end
  end

  @doc """
  True for time-block-backed entries. These are auto-primed from availability
  windows and don't appear in the floating-pool sidebar (users don't drag
  them around).
  """
  def time_block?(%{time_block_id: id}) when not is_nil(id), do: true
  def time_block?(_), do: false

  @doc """
  True when the entry targets a recurring todo. Per-cycle Done/Skip
  semantics apply; destroying the entry would be wrong because prime
  would just recreate it on the next page load.
  """
  def recurring?(%{todo: %{recurrence: r}}) when r in [:weekly, :biweekly, :monthly],
    do: true

  def recurring?(_), do: false
end
