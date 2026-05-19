defmodule Electricbrain.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Electricbrain.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Electricbrain.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Electricbrain.DataCase
    end
  end

  @doc """
  Inserts a user directly via Ash.Seed, bypassing the register flow (and its
  after-actions like default-category seeding). Tests that want the seeded
  defaults should call `Electricbrain.Categories.seed_defaults_for/1` explicitly.
  """
  def create_user!(email \\ nil) do
    email = email || "user-#{System.unique_integer([:positive])}@example.com"

    Ash.Seed.seed!(Electricbrain.Accounts.User, %{
      email: email,
      hashed_password: Bcrypt.hash_pwd_salt("password1234"),
      confirmed_at: DateTime.utc_now()
    })
  end

  setup tags do
    Electricbrain.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Electricbrain.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
