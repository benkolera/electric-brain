defmodule Electricbrain.GoogleCalendarTest do
  use Electricbrain.DataCase, async: true

  alias Electricbrain.Accounts.User
  alias Electricbrain.Categories
  alias Electricbrain.GoogleCalendar
  alias Electricbrain.Planner.Entry
  alias Electricbrain.Todos.Todo

  setup do
    Application.put_env(:electricbrain, :google_client_id, "test-client")
    Application.put_env(:electricbrain, :google_client_secret, "test-secret")

    user =
      create_user!()
      |> connect_google(refresh_token: "rt", access_token: "at", expires_in: 3600)

    :ok = Categories.seed_defaults_for(user)
    inbox = Categories.inbox_for(user)

    todo =
      Todo
      |> Ash.Changeset.for_create(
        :create,
        %{title: "Walk dog", category_id: inbox.id, duration_minutes: 30},
        actor: user
      )
      |> Ash.create!()

    entry =
      Entry
      |> Ash.Changeset.for_create(
        :create,
        %{
          todo_id: todo.id,
          week_start: ~D[2026-05-18],
          planned_at: ~U[2026-05-20 18:00:00.000000Z]
        },
        actor: user
      )
      |> Ash.create!()

    entry = Ash.load!(entry, [:todo, :habit], actor: user)

    {:ok, user: user, entry: entry}
  end

  describe "connected?/1" do
    test "true when refresh_token is present", %{user: user} do
      assert GoogleCalendar.connected?(user)
    end

    test "false otherwise" do
      assert refute_connected(%User{})
    end
  end

  describe "push_event/2 (insert)" do
    test "POSTs to Google and returns the new event id", %{user: user, entry: entry} do
      req =
        Req.new(
          plug: fn conn ->
            assert conn.method == "POST"
            assert conn.request_path == "/calendar/v3/calendars/primary/events"

            {:ok, body, conn} = Plug.Conn.read_body(conn)
            {:ok, payload} = Jason.decode(body)
            assert payload["summary"] == "Walk dog"
            assert payload["start"]["dateTime"] =~ "2026-05-20"

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => "evt_123"}))
          end
        )

      assert {:ok, "evt_123"} = GoogleCalendar.push_event(user, entry, req: req)
    end
  end

  describe "push_event/2 (update)" do
    test "PUTs when entry has google_event_id", %{user: user, entry: entry} do
      entry = Map.put(entry, :google_event_id, "evt_existing")

      req =
        Req.new(
          plug: fn conn ->
            assert conn.method == "PUT"
            assert conn.request_path =~ "/events/evt_existing"

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => "evt_existing"}))
          end
        )

      assert {:ok, "evt_existing"} = GoogleCalendar.push_event(user, entry, req: req)
    end
  end

  describe "delete_event/2" do
    test "DELETEs from Google", %{user: user, entry: entry} do
      entry = Map.put(entry, :google_event_id, "evt_doomed")

      req =
        Req.new(
          plug: fn conn ->
            assert conn.method == "DELETE"
            assert conn.request_path =~ "/events/evt_doomed"
            Plug.Conn.send_resp(conn, 204, "")
          end
        )

      assert :ok = GoogleCalendar.delete_event(user, entry, req: req)
    end

    test "is a no-op when entry has no google_event_id", %{user: user, entry: entry} do
      assert :ok = GoogleCalendar.delete_event(user, entry)
    end

    test "treats 404 as success (already gone)", %{user: user, entry: entry} do
      entry = Map.put(entry, :google_event_id, "evt_gone")

      req =
        Req.new(
          plug: fn conn ->
            Plug.Conn.send_resp(conn, 404, "{}")
          end
        )

      assert :ok = GoogleCalendar.delete_event(user, entry, req: req)
    end
  end

  describe "ensure_fresh_token/2 (refresh)" do
    test "refreshes the access token when expired", %{entry: entry} do
      user =
        create_user!()
        |> connect_google(
          refresh_token: "rt2",
          access_token: "stale",
          expires_in: -10
        )

      :ok = Categories.seed_defaults_for(user)
      _ = entry

      req =
        Req.new(
          plug: fn conn ->
            cond do
              conn.request_path == "/token" ->
                conn
                |> Plug.Conn.put_resp_content_type("application/json")
                |> Plug.Conn.send_resp(
                  200,
                  Jason.encode!(%{"access_token" => "fresh", "expires_in" => 3600})
                )

              true ->
                Plug.Conn.send_resp(conn, 500, "unexpected")
            end
          end
        )

      # Point the module at our test endpoint via the Req fixture; the real
      # module hits oauth2.googleapis.com/token, but since we pass a custom
      # Req with a plug, only the request_path matters for matching.
      assert {:ok, refreshed} = GoogleCalendar.ensure_fresh_token(user, req)
      assert refreshed.google_access_token == "fresh"
    end
  end

  defp connect_google(user, opts) do
    expires_at = DateTime.add(DateTime.utc_now(), Keyword.get(opts, :expires_in, 3600), :second)

    user
    |> Ash.Changeset.for_update(
      :connect_google,
      %{
        google_email: "user@example.com",
        google_access_token: Keyword.fetch!(opts, :access_token),
        google_refresh_token: Keyword.fetch!(opts, :refresh_token),
        google_token_expires_at: expires_at
      },
      actor: user
    )
    |> Ash.update!()
  end

  defp refute_connected(user), do: not GoogleCalendar.connected?(user)
end
