defmodule Electricbrain.Devices do
  @moduledoc """
  Per-user device pairings for external clients that read Trellis state
  over HTTP — currently the Even Hub plugin for Even Realities G2 smart
  glasses, but the shape is generic.

  Pairing model: the user generates a short-lived 6-char code in
  Settings, types it into the external client, the client posts the
  code to `/api/g2/pair`, and the server consumes the code in exchange
  for an opaque long-lived bearer token. Only the SHA-256 hash of the
  token is stored — the cleartext is shown to the client exactly once.
  """

  use Ash.Domain,
    otp_app: :electricbrain

  require Ash.Query

  alias Electricbrain.Devices.Pairing
  alias Electricbrain.Devices.PairingCode

  resources do
    resource Electricbrain.Devices.Pairing
    resource Electricbrain.Devices.PairingCode
  end

  @code_alphabet ~c"ABCDEFGHJKMNPQRSTUVWXYZ23456789"
  @code_length 6
  @code_ttl_seconds 600
  @token_bytes 32

  @doc """
  Generates a new 6-char pairing code for the user with a 10-minute TTL.
  Any existing unconsumed codes for the user are destroyed first so the
  Settings UI only ever shows one live code at a time.
  """
  def generate_code!(user) do
    PairingCode
    |> Ash.Query.filter(user_id == ^user.id)
    |> Ash.read!(actor: user)
    |> Enum.each(&Ash.destroy!(&1, actor: user))

    expires_at = DateTime.add(DateTime.utc_now(), @code_ttl_seconds, :second)
    code = random_code()

    PairingCode
    |> Ash.Changeset.for_create(:generate, %{code: code, expires_at: expires_at}, actor: user)
    |> Ash.create!()
  end

  @doc """
  Consumes a pairing code and issues a new Pairing for the code's owning
  user. Returns `{:ok, %{pairing: %Pairing{}, token: <cleartext>}}` on
  success, or `{:error, :invalid | :expired}`.

  Authorisation: this runs without an actor (the client doesn't have a
  session yet) but only succeeds for a present, unexpired code. Run as
  `authorize?: false` because the policy gate is the code itself.
  """
  def redeem_code(code, label) when is_binary(code) and is_binary(label) do
    case PairingCode
         |> Ash.Query.filter(code == ^code)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        {:error, :invalid}

      {:ok, %PairingCode{} = pairing_code} ->
        if DateTime.compare(pairing_code.expires_at, DateTime.utc_now()) == :lt do
          Ash.destroy!(pairing_code, authorize?: false)
          {:error, :expired}
        else
          {token, hash} = mint_token()
          user_id = pairing_code.user_id

          pairing =
            Pairing
            |> Ash.Changeset.for_create(
              :issue,
              %{token_hash: hash, label: label, user_id: user_id},
              authorize?: false
            )
            |> Ash.create!()

          Ash.destroy!(pairing_code, authorize?: false)
          {:ok, %{pairing: pairing, token: token}}
        end
    end
  end

  @doc """
  Issues an `:ingest` pairing directly (no code exchange — the token is
  pasted into a relay app like Health Auto Export rather than redeemed
  by an interactive client). Returns `%{pairing: pairing, token: cleartext}`;
  the cleartext is shown exactly once.
  """
  def create_ingest_token!(user, label) do
    {token, hash} = mint_token()

    pairing =
      Pairing
      |> Ash.Changeset.for_create(
        :issue,
        %{token_hash: hash, label: label, user_id: user.id, kind: :ingest},
        authorize?: false
      )
      |> Ash.create!()

    %{pairing: pairing, token: token}
  end

  @doc """
  Looks up the Pairing for an opaque bearer token. Returns `{:ok,
  {pairing, user}}` or `:error`. Side effect: bumps `last_seen_at`.
  """
  def lookup_token(token) when is_binary(token) do
    hash = hash_token(token)

    case Pairing
         |> Ash.Query.filter(token_hash == ^hash)
         |> Ash.Query.load(:user)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        :error

      {:ok, %Pairing{user: user} = pairing} ->
        _ =
          pairing
          |> Ash.Changeset.for_update(:touch, %{}, authorize?: false)
          |> Ash.update()

        {:ok, {pairing, user}}
    end
  end

  @doc """
  PubSub topic used to nudge the SSE stream for a user out-of-band
  (e.g. the "Send test push" button on the Settings page). Distinct
  from `Agenda.topic/1` and `Focus.Scheduler.topic/1` so the test
  payload never gets confused with a real state-change broadcast.
  """
  def test_topic(user_id), do: "g2:user:#{user_id}:test"

  @doc """
  Broadcasts a `:test_push` message on the user's test topic. The
  SSE controller subscribes to this and emits a `change` event so
  the plugin can wake the HUD as a connectivity check.
  """
  def send_test_push(user) do
    Phoenix.PubSub.broadcast(
      Electricbrain.PubSub,
      test_topic(user.id),
      :test_push
    )
  end

  @doc """
  Composes the user-facing API state — current/next planner entry,
  active focus session, and today's habits with this-period progress.
  Shape is fixed by the `/api/g2/state` JSON contract.
  """
  def state_for(user) do
    %{
      now: now_payload(user),
      next: next_payload(user),
      focus: focus_payload(user),
      habits_today: habits_today_payload(user)
    }
  end

  defp now_payload(user) do
    %{current: current, next: _} = Electricbrain.Agenda.state(user.id)

    case current do
      [] ->
        nil

      [item | _] ->
        now = DateTime.utc_now()

        %{
          title: Electricbrain.Planner.EntryTarget.title(item.entry),
          ends_at: item.end_time,
          ends_in_s: Kernel.max(0, DateTime.diff(item.end_time, now, :second))
        }
    end
  end

  defp next_payload(user) do
    %{next: next} = Electricbrain.Agenda.state(user.id)

    case next do
      nil ->
        nil

      item ->
        now = DateTime.utc_now()

        %{
          title: Electricbrain.Planner.EntryTarget.title(item.entry),
          starts_at: item.entry.planned_at,
          starts_in_s: Kernel.max(0, DateTime.diff(item.entry.planned_at, now, :second))
        }
    end
  end

  defp focus_payload(user) do
    case Electricbrain.Focus.Session
         |> Ash.Query.filter(status in [:running, :on_break])
         |> Ash.Query.load([:todo, :habit, :time_block, :category])
         |> Ash.read_one(actor: user) do
      {:ok, nil} ->
        nil

      {:ok, %Electricbrain.Focus.Session{} = session} ->
        {ends_at, state} = focus_ends_at(session)
        now = DateTime.utc_now()

        %{
          state: state,
          target: focus_target_label(session),
          ends_at: ends_at,
          ends_in_s: Kernel.max(0, DateTime.diff(ends_at, now, :second))
        }
    end
  end

  defp focus_ends_at(%Electricbrain.Focus.Session{
         status: :running,
         started_at: started_at,
         duration_minutes: mins
       }) do
    {DateTime.add(started_at, mins * 60, :second), :work}
  end

  defp focus_ends_at(%Electricbrain.Focus.Session{
         status: :on_break,
         break_started_at: started_at,
         break_minutes: mins
       }) do
    {DateTime.add(started_at, mins * 60, :second), :break}
  end

  defp focus_target_label(%{todo: %{title: t}}) when is_binary(t), do: t
  defp focus_target_label(%{habit: %{title: t}}) when is_binary(t), do: t
  defp focus_target_label(%{time_block: %{title: t}}) when is_binary(t), do: t
  defp focus_target_label(%{category: %{name: n}}) when is_binary(n), do: n
  defp focus_target_label(_), do: nil

  defp habits_today_payload(user) do
    tz = user.timezone || "Etc/UTC"
    now = DateTime.utc_now()

    Electricbrain.Habits.Habit
    |> Ash.Query.filter(period in [:day, :week, :month])
    |> Ash.Query.load(:completions)
    |> Ash.read!(actor: user)
    |> Enum.map(fn habit ->
      period_start = Electricbrain.Timezones.period_start(habit.period, tz, now)

      done =
        Enum.count(habit.completions, fn c ->
          c.completed_at && DateTime.compare(c.completed_at, period_start) != :lt
        end)

      %{
        title: habit.title,
        done: done,
        target: habit.min_count,
        period: habit.period
      }
    end)
    # Day-period: always include (today's check). Week/month: only when
    # still owed — the HUD is a nudge, not a status board.
    |> Enum.filter(fn h -> h.period == :day or h.done < h.target end)
    |> Enum.sort_by(fn h ->
      remaining = h.target - h.done
      # Day-period incomplete first, then by how much is still owed.
      {if(h.period == :day and remaining > 0, do: 0, else: 1), -remaining, h.title}
    end)
    |> Enum.take(10)
  end

  # ---- internal: token / code helpers ----

  defp mint_token do
    token = :crypto.strong_rand_bytes(@token_bytes) |> Base.url_encode64(padding: false)
    {token, hash_token(token)}
  end

  defp hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  defp random_code do
    1..@code_length
    |> Enum.map(fn _ -> Enum.random(@code_alphabet) end)
    |> List.to_string()
  end
end
