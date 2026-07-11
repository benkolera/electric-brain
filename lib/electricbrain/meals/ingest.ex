defmodule Electricbrain.Meals.Ingest do
  @moduledoc """
  Turns webhook payloads into Measurement rows on the profile-mapped
  metrics. Two payload shapes are accepted:

  Generic:

      {"measurements": [
        {"metric": "weight", "value": 82.5, "recorded_at": "2026-07-11T07:12:00Z"}
      ]}

  Health Auto Export (the Hume scale relay — Hume has no public API,
  but the Body Pod syncs to Apple Health and the Health Auto Export
  iOS app POSTs Apple Health data on a schedule):

      {"data": {"metrics": [
        {"name": "weight_body_mass", "units": "kg",
         "data": [{"qty": 82.5, "date": "2026-07-11 07:12:00 +1000"}]}
      ]}}

  Key mapping: `weight`/`weight_body_mass` → the profile's weight
  metric; `body_fat_pct`/`body_fat_percentage` → the body-fat metric.
  Unmapped or unknown keys are reported back, not stored.

  Parsing is LENIENT per entry: HAE exports carry data points without
  a plain `qty` for many metric types (heart rate is min/avg/max,
  sleep is phase fields), so entries that don't match are counted as
  `skipped` — and logged — rather than failing the whole sync. Only an
  unrecognisable envelope 422s. Duplicate posts are idempotent — a
  reading with the same metric and timestamp is skipped as
  `duplicates`.
  """

  require Ash.Query
  require Logger

  alias Electricbrain.Meals
  alias Electricbrain.Metrics.Measurement

  @key_aliases %{
    "weight" => :weight,
    "weight_body_mass" => :weight,
    "body_fat_pct" => :body_fat,
    "body_fat_percentage" => :body_fat
  }

  @doc """
  Returns `{:ok, %{created: n, duplicates: n, skipped: n, unmapped: [key]}}`
  or `{:error, :invalid_payload}` (unrecognisable envelope only).
  """
  def ingest(user, payload) do
    with {:ok, %{readings: readings, skipped: skipped}} <- normalise(payload) do
      mapping = metric_mapping(user)

      result =
        Enum.reduce(
          readings,
          %{created: 0, duplicates: 0, skipped: skipped, unmapped: MapSet.new()},
          fn reading, acc ->
            case Map.fetch(mapping, @key_aliases[reading.key]) do
              {:ok, metric_id} when is_binary(metric_id) ->
                case insert(user, metric_id, reading) do
                  :created -> %{acc | created: acc.created + 1}
                  :duplicate -> %{acc | duplicates: acc.duplicates + 1}
                end

              _ ->
                %{acc | unmapped: MapSet.put(acc.unmapped, reading.key)}
            end
          end
        )

      {:ok, %{result | unmapped: Enum.sort(result.unmapped)}}
    end
  end

  defp metric_mapping(user) do
    case Meals.profile_for(user) do
      nil -> %{}
      profile -> %{weight: profile.weight_metric_id, body_fat: profile.body_fat_metric_id}
    end
  end

  # --- payload shapes ---------------------------------------------------

  defp normalise(%{"measurements" => measurements}) when is_list(measurements) do
    collect(measurements, fn
      %{"metric" => key, "value" => value, "recorded_at" => at}
      when is_binary(key) and is_number(value) ->
        with {:ok, recorded_at} <- parse_datetime(at) do
          {:ok, %{key: key, value: value, recorded_at: recorded_at}}
        end

      _ ->
        :error
    end)
  end

  defp normalise(%{"data" => %{"metrics" => metrics}}) when is_list(metrics) do
    metrics
    |> Enum.flat_map(fn
      %{"name" => key, "data" => data} when is_binary(key) and is_list(data) ->
        Enum.map(data, &{key, &1})

      other ->
        # A metric entry without a name/data list — count as one skip.
        [{:invalid_metric, other}]
    end)
    |> collect(fn
      {key, %{"qty" => qty, "date" => date}} when is_binary(key) and is_number(qty) ->
        with {:ok, recorded_at} <- parse_datetime(date) do
          {:ok, %{key: key, value: qty, recorded_at: recorded_at}}
        end

      _ ->
        :error
    end)
  end

  defp normalise(payload) do
    Logger.warning(
      "Ingest: unrecognisable payload envelope, top-level keys: " <>
        inspect(payload |> Map.keys() |> Enum.take(10))
    )

    {:error, :invalid_payload}
  end

  # Lenient per-entry collection: parse what matches, count the rest as
  # skipped (and log which keys they came from — HAE exports routinely
  # include shapes we don't ingest, like min/avg/max metrics).
  defp collect(items, fun) do
    {readings, skipped_items} =
      Enum.reduce(items, {[], []}, fn item, {readings, skipped} ->
        case fun.(item) do
          {:ok, reading} -> {[reading | readings], skipped}
          _ -> {readings, [item | skipped]}
        end
      end)

    if skipped_items != [] do
      Logger.warning(
        "Ingest: skipped #{length(skipped_items)} unparseable entries " <>
          "(keys: #{inspect(skipped_keys(skipped_items))})"
      )
    end

    {:ok, %{readings: Enum.reverse(readings), skipped: length(skipped_items)}}
  end

  defp skipped_keys(items) do
    items
    |> Enum.map(fn
      {key, _point} when is_binary(key) -> key
      {:invalid_metric, _} -> "(metric without name/data)"
      %{"metric" => key} when is_binary(key) -> key
      _ -> "(unknown)"
    end)
    |> Enum.uniq()
    |> Enum.take(10)
  end

  # ISO8601 directly, or Health Auto Export's "yyyy-MM-dd HH:mm:ss Z"
  # (space separators, e.g. "2026-07-11 07:12:00 +1000").
  defp parse_datetime(value) when is_binary(value) do
    iso =
      value
      |> String.replace(" ", "T", global: false)
      |> String.replace(" +", "+")
      |> String.replace(" -", "-")

    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> {:ok, DateTime.shift_zone!(dt, "Etc/UTC")}
      _ -> :error
    end
  end

  defp parse_datetime(_), do: :error

  # --- persistence ------------------------------------------------------

  defp insert(user, metric_id, reading) do
    existing =
      Measurement
      |> Ash.Query.filter(metric_id == ^metric_id and recorded_at == ^reading.recorded_at)
      |> Ash.read!(actor: user)

    if existing == [] do
      Measurement
      |> Ash.Changeset.for_create(
        :create,
        %{
          metric_id: metric_id,
          value: to_decimal(reading.value),
          recorded_at: reading.recorded_at
        },
        actor: user
      )
      |> Ash.create!()

      :created
    else
      :duplicate
    end
  end

  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
end
