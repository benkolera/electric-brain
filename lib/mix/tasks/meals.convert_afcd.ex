defmodule Mix.Tasks.Meals.ConvertAfcd do
  @shortdoc "Convert a FSANZ AFCD nutrient-profiles CSV export into priv/meals/afcd_ingredients.csv"

  @moduledoc """
  One-off conversion of the Australian Food Composition Database into the
  normalised ingredient seed file committed at
  `priv/meals/afcd_ingredients.csv`.

      mix meals.convert_afcd path/to/afcd-nutrient-profiles.csv

  Input: the "All solids & liquids per 100 g" sheet of the FSANZ
  "AFCD Release 3 - Nutrient profiles.xlsx" download
  (https://www.foodstandards.gov.au/science-data/food-nutrient-databases/afcd/data-files),
  exported to CSV from a spreadsheet app. The task locates the header row
  by the "Public Food Key" cell, so leading title rows are fine.

  Column mapping (per 100 g):

    * `afcd_code`  — "Public Food Key"
    * `name`       — "Food Name"
    * `kcal`       — "Energy with dietary fibre, equated (kJ)" ÷ 4.184
    * `protein_g`  — "Protein (g)"
    * `fat_g`      — "Fat, total (g)"
    * `carbs_g`    — "Available carbohydrate, with sugar alcohols (g)"
    * `fibre_g`    — "Total dietary fibre (g)"

  Blank nutrient cells become 0; rows missing a food key, name, or energy
  value are skipped. AFCD is CC-BY 4.0 — © Food Standards Australia
  New Zealand.
  """

  use Mix.Task

  alias NimbleCSV.RFC4180, as: CSV

  @out_path "priv/meals/afcd_ingredients.csv"

  @headers %{
    code: "Public Food Key",
    name: "Food Name",
    kj: "Energy with dietary fibre",
    protein: "Protein",
    fat: "Fat, total",
    carbs: "Available carbohydrate, with sugar alcohols",
    fibre: "Total dietary fibre"
  }

  @impl true
  def run([input_path]) do
    rows =
      input_path
      |> File.read!()
      |> CSV.parse_string(skip_headers: false)

    {header, data} = split_at_header(rows)
    cols = column_indexes(header)

    out_rows =
      data
      |> Enum.flat_map(&convert_row(&1, cols))

    out =
      CSV.dump_to_iodata([
        ~w(afcd_code name kcal_per_100g protein_g_per_100g fat_g_per_100g carbs_g_per_100g fibre_g_per_100g)
        | out_rows
      ])

    File.write!(@out_path, out)
    Mix.shell().info("Wrote #{length(out_rows)} ingredients to #{@out_path}")
  end

  def run(_) do
    Mix.raise("Usage: mix meals.convert_afcd path/to/afcd-nutrient-profiles.csv")
  end

  defp split_at_header(rows) do
    case Enum.split_while(rows, fn row -> not Enum.member?(row, @headers.code) end) do
      {_, [header | data]} -> {header, data}
      _ -> Mix.raise("No header row containing \"#{@headers.code}\" found")
    end
  end

  defp column_indexes(header) do
    Map.new(@headers, fn {key, prefix} ->
      case Enum.find_index(header, &String.starts_with?(String.trim(&1), prefix)) do
        nil -> Mix.raise("Column starting with \"#{prefix}\" not found in header row")
        idx -> {key, idx}
      end
    end)
  end

  defp convert_row(row, cols) do
    code = cell(row, cols.code)
    name = cell(row, cols.name)
    kj = cell(row, cols.kj)

    if code == "" or name == "" or kj == "" do
      []
    else
      kcal = Float.round(to_float(kj) / 4.184, 1)

      [
        [
          code,
          name,
          format(kcal),
          format(to_float(cell(row, cols.protein))),
          format(to_float(cell(row, cols.fat))),
          format(to_float(cell(row, cols.carbs))),
          format(to_float(cell(row, cols.fibre)))
        ]
      ]
    end
  end

  defp cell(row, idx), do: row |> Enum.at(idx, "") |> String.trim()

  defp to_float(value) do
    case Float.parse(value) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp format(f), do: :erlang.float_to_binary(Float.round(f, 2), [:compact, decimals: 2])
end
