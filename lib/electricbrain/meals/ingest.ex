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
  Unmapped or unknown keys are reported back, not stored. Duplicate
  posts are idempotent — a reading with the same metric and timestamp
  is skipped.
  """

  require Ash.Query

  alias Electricbrain.Meals
  alias Electricbrain.Metrics.Measurement

  @key_aliases %{
    "weight" => :weight,
    "weight_body_mass" => :weight,
    "body_fat_pct" => :body_fat,
    "body_fat_percentage" => :body_fat
  }

  @doc """
  Returns `{:ok, %{created: n, duplicates: n, unmapped: [key]}}` or
  `{:error, :invalid_payload}`.
  """
  def ingest(user, payload) do
    with {:ok, readings} <- normalise(payload) do
      mapping = metric_mapping(user)

      result =
        Enum.reduce(readings, %{created: 0, duplicates: 0, unmapped: MapSet.new()}, fn reading,
                                                                                       acc ->
          case Map.fetch(mapping, @key_aliases[reading.key]) do
            {:ok, metric_id} when is_binary(metric_id) ->
              case insert(user, metric_id, reading) do
                :created -> %{acc | created: acc.created + 1}
                :duplicate -> %{acc | duplicates: acc.duplicates + 1}
              end

            _ ->
              %{acc | unmapped: MapSet.put(acc.unmapped, reading.key)}
          end
        end)

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

      _ ->
        [:invalid]
    end)
    |> collect(fn
      {key, %{"qty" => qty, "date" => date}} when is_number(qty) ->
        with {:ok, recorded_at} <- parse_datetime(date) do
          {:ok, %{key: key, value: qty, recorded_at: recorded_at}}
        end

      _ ->
        :error
    end)
  end

  defp normalise(_), do: {:error, :invalid_payload}

  defp collect(items, fun) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, reading} -> {:cont, {:ok, [reading | acc]}}
        _ -> {:halt, {:error, :invalid_payload}}
      end
    end)
    |> case do
      {:ok, readings} -> {:ok, Enum.reverse(readings)}
      error -> error
    end
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
