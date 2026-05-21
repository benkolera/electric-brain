# Electric Brain

A second-brain app organised around **balance across life areas**, not
throughput. The north-star use case is a Sunday planning ritual: look
at the week behind, place habits and todos onto the week ahead, sync
the result to Google Calendar, then live the plan.

Phoenix 1.8 + LiveView + [Ash], Postgres + AshPostgres, Tailwind v4.
Single Phoenix app — no umbrella. Deployed as half of the
[benkolera-poncho] bundle alongside [pack-heavy].

[Ash]: https://ash-hq.org
[benkolera-poncho]: https://github.com/benkolera/benkolera-poncho
[pack-heavy]: https://github.com/benkolera/pack-heavy

## What it does

- **Categories** — a strict tree (no tags) of life areas: Health,
  Work, Relationships, Hobbies, etc. Each category gets a colour
  from Google's 11-colour calendar palette; children inherit unless
  they override. The tree surfaces neglect (how much time has rolled
  past without each area being touched).
- **Todos** — one-off intents pinned to a category, optionally with
  a duration. Surface in the planner pool when their week comes around.
- **Habits** — recurring count-based intents ("3× per week"). Track
  completions per period; the streak heatmap + "don't miss twice"
  badge surface chains at risk. Each habit can carry an *identity
  statement* (Atomic Habits ch. 2) and a *two-minute fallback*
  (ch. 13). Habits can have ordered ritual steps (e.g. a morning
  routine) whose checks are tracked per completion.
- **Time blocks** — distinct from habits: tracked time slots (Sleep,
  Work) with weekly targets (`at_least 56h`, `at_most 50h`).
  Auto-placed onto the planner from availability windows. Lives in
  its own Ash domain so habit features (streaks, identity) don't
  conflict.
- **Notes** — markdown-rendered freeform notes, also pinned to a
  category.
- **Planner** — weekly calendar (Schedule-X), drag-and-drop scheduling
  of todos/habits from a floating pool onto a time grid. Auto-primed
  with time-block availability each week. Per-category planned-time
  tree shows where the week's hours actually go.
- **Weekly review** — Atomic Habits ch. 20. Per-habit reflection
  with a 1-5 Goldilocks difficulty rating and freeform notes.
- **Metrics** — Beeminder-style numeric series. Each metric has a
  unit and an aggregation (point-in-time or summed per period);
  related metrics share a `group_name` so they cluster on one chart
  (Deadlift 1RM/3RM/8RM). Measurements can be entered manually
  (with backfill) or captured at habit completion — attach metrics
  to a habit, complete it, and a prompt asks for each value before
  the completion finalises. Each metric can carry a flat
  "yellow brick road" goal (`at_least` / `at_most` × a value per
  day/week/month); the chart overlays the road line and an on-track /
  off-track pill shows the current bucket's standing.
- **Moments** — radical-acceptance pauses (Tara Brach's RAIN: Recognize,
  Allow, Investigate, Nurture). When a craving, urge or feeling pulls,
  open the floating "Pause" button, name what's there, slide an intensity,
  and optionally journal through the four RAIN prompts. Designed to be
  mobile-quick — minimum required is the name and intensity. History
  page lists past moments filtered by kind.
- **Google Calendar push** — one-way sync from the planner to the
  user's primary calendar. Idempotent via stored `google_event_id`;
  category colour drives the event colour.
- **Web push notifications** — opt-in per browser. The Settings page
  has Enable / Send test / per-device disable. A cron-driven
  scheduler (`Notifications.Scheduler`) fires a push 5 min before
  each planner entry's start. VAPID keys configured via
  `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` env vars in prod;
  `mix generate.vapid.keys` to mint a pair.

## Architecture

```mermaid
flowchart LR
    user([User])

    user -->|"sign in"| auth0[Auth0 Tenant]
    user --> liveview

    subgraph phx["Phoenix 1.8 · LiveView"]
        liveview["Planner / Habits /<br/>Categories / Notes / …"]
    end

    subgraph ash["Ash Domains"]
        direction TB
        accounts[Accounts<br/>User + Token]
        categories[Categories<br/>Category tree]
        todos[Todos]
        habits[Habits<br/>+ Completion<br/>+ RitualStep<br/>+ Reflection]
        timeblocks[TimeBlocks]
        planner[Planner.Entry]
        notes[Notes]
        metrics[Metrics<br/>+ Measurement<br/>+ HabitMetric]
        moments[Moments<br/>RAIN journal]
        notifications[Notifications<br/>PushSubscription]
    end

    liveview --> accounts
    liveview --> categories
    liveview --> todos
    liveview --> habits
    liveview --> timeblocks
    liveview --> planner
    liveview --> notes
    liveview --> metrics
    liveview --> moments

    todos --> categories
    habits --> categories
    timeblocks --> categories
    notes --> categories
    metrics --> categories
    moments --> categories

    planner -->|"todo_id or<br/>habit_id or<br/>time_block_id"| todos
    planner --> habits
    planner --> timeblocks

    metrics -->|"HabitMetric join +<br/>Measurement.completion_id"| habits

    notifications -.->|"5-min lead<br/>cron tick"| planner
    notifications -.->|"web push"| pushsvc[Browser<br/>Push Service]

    planner -.->|"sync"| gcal[Google<br/>Calendar API]

    auth0 -.->|"OAuth callback"| accounts
```

Every plannable thing — todo, habit, time block — points back at a
category, which is the unit of "this is a part of my life". The
planner just maps `(category, intent) → time on the calendar`. The
neglect score rolls up the category tree to highlight areas you've
underweighted.

**Stack notes:**

- **Ash, not raw Ecto** — Resources, actions, policies. Migrations
  generated via `mix ash.codegen`. The exception is one-shot data
  moves (e.g. splitting time blocks out of habits) which are
  manual Ecto migrations.
- **Schedule-X** for the planner calendar — wired in via a LiveView
  `phx-hook` with `phx-update="ignore"`; drag/click events round-trip
  through `pushEvent`. Calendar configs registered for all 11
  Google colours so events styled with `calendarId` pick up the
  right hex.
- **Auth0** for sign-in in prod; password strategy in dev/test via
  a `Mix.env() in [:dev, :test]` guard on the `password` block.
- **No daisyUI** — hand-rolled Tailwind components, per the
  `AGENTS.md` convention.

## Running locally

```bash
mix setup            # deps.get, ash.setup, assets.setup + build, seeds
mix phx.server       # http://localhost:4000
```

The dev environment uses the `password` auth strategy (Auth0 is only
compiled in for prod). A default user gets seeded; check
`priv/repo/seeds.exs`.

Prod runtime expects these environment variables (set by the poncho
bundle's `runtime.exs` when deployed):

- `DATABASE_URL`, `SECRET_KEY_BASE`, `TOKEN_SIGNING_SECRET`
- `AUTH0_DOMAIN`, `AUTH0_CLIENT_ID`, `AUTH0_CLIENT_SECRET`
- Optional: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` (calendar push)

## Tests

```bash
mix test
```

Tests use real Postgres (no mocking — `ash.setup --quiet` runs first,
configured via the `test:` alias in `mix.exs`).

## Deployment

This app is deployed as part of [benkolera-poncho] — a separate repo
that bundles electric-brain + pack-heavy into one Fargate task on
shared AWS infrastructure. See the poncho's README for the runtime
architecture and release flow.

For day-to-day work: commit + push here, then run `release.sh` in
the poncho repo to bump the submodule pointer and ship.
