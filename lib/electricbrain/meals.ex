defmodule Electricbrain.Meals do
  use Ash.Domain,
    otp_app: :electricbrain

  resources do
    resource Electricbrain.Meals.Ingredient
  end
end
