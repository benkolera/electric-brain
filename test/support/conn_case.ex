defmodule ElectricbrainWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use ElectricbrainWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint ElectricbrainWeb.Endpoint

      use ElectricbrainWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import ElectricbrainWeb.ConnCase
      import Electricbrain.DataCase, only: [create_user!: 0, create_user!: 1]
    end
  end

  setup tags do
    Electricbrain.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Logs the given user in by issuing a JWT and storing it in the session.

  Also registers a teardown that stops the user's `Electricbrain.Agenda`
  GenServer. Any connected LiveView mount spawns one (LiveUserAuth's
  agenda hook), and it would otherwise outlive the test's SQL sandbox —
  a later DB call from the leaked actor tears down the shared sandbox
  connection and flakes whichever test is running at the time. This
  on_exit runs before `setup_sandbox`'s owner shutdown (LIFO), so the
  actor dies while its connection owner is still alive.
  """
  def log_in_user(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    user = Ash.Resource.put_metadata(user, :token, token)

    ExUnit.Callbacks.on_exit(fn -> Electricbrain.Agenda.stop(user.id) end)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end
end
