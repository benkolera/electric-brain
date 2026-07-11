defmodule Electricbrain.Meals.SeederTest do
  use Electricbrain.DataCase, async: true

  require Ash.Query

  alias Electricbrain.Meals.Ingredient
  alias Electricbrain.Meals.Seeder

  @header "afcd_code,name,kcal_per_100g,protein_g_per_100g,fat_g_per_100g,carbs_g_per_100g,fibre_g_per_100g"

  defp write_csv!(dir, rows) do
    path = Path.join(dir, "afcd.csv")
    File.write!(path, Enum.join([@header | rows], "\n") <> "\n")
    path
  end

  @tag :tmp_dir
  test "seeds global rows and is idempotent, updating values in place", %{tmp_dir: dir} do
    path =
      write_csv!(dir, [
        ~s(F001,"Chicken breast, grilled",165.0,31.0,3.6,0.0,0.0),
        ~s(F002,"Broccoli, raw",34.0,2.8,0.4,4.4,3.3)
      ])

    assert Seeder.seed_afcd!(path) == 2

    # Re-seed with a corrected value: no new rows, value updated.
    path =
      write_csv!(dir, [
        ~s(F001,"Chicken breast, grilled",170.0,31.0,3.6,0.0,0.0),
        ~s(F002,"Broccoli, raw",34.0,2.8,0.4,4.4,3.3)
      ])

    assert Seeder.seed_afcd!(path) == 2

    rows = Ash.read!(Ingredient, authorize?: false)
    assert length(rows) == 2

    chicken = Enum.find(rows, &(&1.afcd_code == "F001"))
    assert Decimal.equal?(chicken.kcal_per_100g, Decimal.new("170.0"))
    assert chicken.source == :afcd
    assert is_nil(chicken.user_id)
  end

  test "the committed AFCD CSV parses and seeds" do
    count = Seeder.seed_afcd!()
    assert count > 1500
  end
end
