defmodule Electricbrain.Meals.Seeder do
  @moduledoc """
  Loads the AFCD ingredient library from `priv/meals/afcd_ingredients.csv`
  into the global (user_id: nil) ingredient rows. Idempotent: rows upsert
  on `afcd_code`, so re-running updates macro values in place and never
  duplicates. Runs from `priv/repo/seeds.exs` in dev and from
  `Electricbrain.Release.migrate/0` in prod.

  The CSV is derived from the FSANZ "Nutrient profiles" Excel file by
  `mix meals.convert_afcd` — see that task for the column mapping.
  """

  alias Electricbrain.Meals.Ingredient
  alias NimbleCSV.RFC4180, as: CSV

  def seed_afcd!(path \\ default_path()) do
    result =
      path
      |> File.stream!()
      |> CSV.parse_stream()
      |> Stream.map(fn [code, name, kcal, protein, fat, carbs, fibre] ->
        %{
          afcd_code: code,
          name: name,
          source: :afcd,
          kcal_per_100g: kcal,
          protein_g_per_100g: protein,
          fat_g_per_100g: fat,
          carbs_g_per_100g: carbs,
          fibre_g_per_100g: fibre
        }
      end)
      |> Ash.bulk_create!(Ingredient, :seed_upsert,
        authorize?: false,
        stop_on_error?: true,
        return_errors?: true,
        return_records?: true
      )

    length(result.records)
  end

  defp default_path do
    Path.join(:code.priv_dir(:electricbrain), "meals/afcd_ingredients.csv")
  end
end
