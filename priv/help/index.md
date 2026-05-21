# Welcome to Trellis

A weekly planning practice built around **balance across life areas**,
not throughput. The north-star use case is a **Sunday planning ritual**:
look at the week behind, place habits and todos onto the week ahead,
sync to your Google Calendar, then live the plan.

This guide walks through the concepts and how the pieces link together.
If you skim one thing, read the next section.

## Why "Trellis"?

A trellis is the wooden frame a vine grows up. It doesn't make the plant
grow — it just gives growth somewhere to attach. The categories you
keep, the habits you commit to, and the weekly ritual itself are the
trellis. Your life is what grows up through it: not faster, not more,
but with better support, in the directions you actually care about.

The app is the trellis. You are the gardener.

## Philosophy

Most planners optimise for getting more done. This one optimises for
**not neglecting the parts of your life that matter**. Every plannable
thing lives under a **category** — Health, Work, Relationships,
Hobbies, Admin — and the planner shows you, at a glance, how the
week's hours actually divide between them.

The weekly ritual is the heart of the system:

1. **Look back** at last week — what got done, what slipped, what felt
   too easy or too hard (the Weekly Review page).
2. **Place** the week ahead onto the calendar — habits, todos, time
   blocks. Aim for balance, not maximisation.
3. **Sync** to Google Calendar so the plan lives where you already look.
4. **Live the plan** — habit completions, ritual checks, capturing
   measurements, pausing when something pulls.

## Categories — your tree of life areas

Categories are a strict tree. Each one has at most one parent. Health
might have child categories Exercise and Sleep. Work might have Deep
Work and Admin. Everything else in the app — todos, habits, time
blocks, notes, metrics, moments — points back at a category, so
neglect rolls up the tree.

The default tree seeds you with Inbox, Work, Health, Hobbies,
Relationships, Admin. Edit it to match how you actually think about
your life. Sub-categories are encouraged.

**Colours** come from Google Calendar's fixed 11-colour palette.
Children inherit unless they override. Root with nothing set falls
back to the default.

## Todos — one-off and recurring intents

A **todo** is something you intend to do, pinned to a category, with
an optional duration. Todos surface in the planner's floating pool
each week; drag them onto a time slot.

Set **Repeats** to make it recurring — weekly, every 2 weeks (your
fortnightly bills/groceries/bin night), or monthly. Pick a **first
instance (anchor)** datetime — that fixes the day-of-week,
day-of-month, time-of-day, and (for fortnightly) the cadence's phase.
The planner auto-creates an entry each cycle.

A recurring entry has two cycle-level actions in addition to the usual
reschedule/unschedule:

- **Done** — marks the cycle done. The entry disappears from the
  agenda and calendar; the next cycle's entry primes on schedule.
- **Skip** — marks the cycle dismissed (didn't do it, not coming back
  this cycle). Same hide behaviour, different history.

To stop recurring entirely, edit the todo back to "(once)". Recurring
todos are never "completed" globally — the cycle is the unit of done.

## Habits — recurring count-based intents

A **habit** is "do this X times per period" — `3× per week`,
`1× per day`. Different from a recurring todo: you're tracking a
count, not a scheduled instance. The streak heatmap on each habit
shows the last 8 weeks; "don't miss twice" surfaces chains at risk.

Habits can carry two pieces of *Atomic Habits* framing:

* **Identity statement** ("…someone who writes every day"). Atomic
  Habits ch. 2: every completion is a vote for who you are.
* **Two-minute fallback**. Ch. 13: a scaled-down version to fall back
  on when energy is low so the streak doesn't break.

Habits can have **ritual steps** — an ordered checklist for each
instance. The habit isn't done until every step is ticked. Step
state persists across sessions so you can come back to it.

Habits can also have **metrics** attached — when you complete the
habit, you're prompted to enter a value for each (see Metrics below).

## Time blocks — recurring tracked time

A **time block** (Sleep, Work, Deep Work) is for slabs of time you
want to track and target, not for tasks. Each has weekly availability
windows; the planner auto-primes those onto the calendar every week.

Optional weekly targets (`at_least 56h` for sleep, `at_most 50h` for
work) let you see whether the week's plan is over or under. Time
blocks live in their own domain, separate from habits, because their
features differ (no streaks, no identity statements, no neglect rollup
in the same way).

## Metrics — Beeminder-style numeric series

Each **metric** is a numeric series with a unit and an aggregation:

* **point-in-time** — the latest value wins per period (weight, 1RM)
* **summed** — values add up per period (water, drinks, calories)

For summed metrics you must pick a **period** (day / week / month)
that defines the bucket size. Related metrics share a `group_name`
(Deadlift 1RM/3RM/8RM all under "Deadlift") so they cluster on one
chart.

Set a flat **yellow brick road** goal (`at_least` or `at_most` a
value) and the chart overlays a dashed line at that value. The
on-track / off-track pill on the metric card shows the current
bucket's standing.

**Measurements** can be entered manually (with backfill — pick any
past datetime) or captured at habit completion. To capture from a
habit: attach the metric to the habit, complete it, and a modal asks
for the value before the completion finalises. Skip if you want to
backfill later.

## Planner — the weekly grid

The `/plan` page is the central surface — a Schedule-X calendar
showing the current week.

* **This-week pool** (left) holds floating todos and habits not yet
  scheduled. Click "Add" to pull from your global pool.
* **Calendar** (middle) is the time grid. Drag to move, resize edges
  to adjust duration. Click a slot to "arm" a floating item and place
  it.
* **Planned tree** (right) shows the per-category total time planned
  this week, rolled up the tree. This is the balance gauge.
* **Sync to Google** pushes everything scheduled to your primary
  Google Calendar. One-way. Idempotent — running it twice doesn't
  duplicate.

Selected entries show an inline edit form for start time + duration
(useful for short entries that are awkward to drag).

## Weekly review

Once a week, head to `/plan/review` for Atomic Habits ch. 20:
per-habit reflection with a 1–5 Goldilocks difficulty rating and
freeform notes. Hard habits got harder? Drop the bar. Too easy?
Raise it. The review is the metacognitive loop that keeps the
weekly plan honest.

## Moments — radical-acceptance pauses

When a craving, urge or strong feeling pulls, hit the **Pause**
button (floating, bottom-right on every page). Name the thing,
slide an intensity, optionally journal through Tara Brach's RAIN
prompts:

* **R**ecognize — what's here right now?
* **A**llow — can I let it be?
* **I**nvestigate — what does it want? Where in the body?
* **N**urture — what does this part of me need?

The fields are all optional — the pause itself is the practice; the
journal is the bonus. History on `/moments` shows past moments
filtered by kind so you can spot patterns over time.

## Notifications

Settings → Notifications → Enable on this device, per browser.
Five minutes before each planned item starts, you get a push.

On iPhone you must install the app to the home screen first —
share → Add to Home Screen → open the installed icon → then Enable.
Safari tabs don't get web push.

## How they link together

The mental model is a thin one:

* **Categories** are the spine. Everything else points at one.
* **Todos, habits, time blocks** are the three kinds of plannable
  thing. Each carries a category. Each can be placed on the planner
  as a calendar entry.
* The **planner** is just the weekly grid view of those entries. It
  groups by category, calculates totals, and rolls them up the tree.
* **Habits** can capture **metrics** at completion time, so a habit
  isn't just a tick — it's a tick plus a measured value if you want.
* **Notifications** read the planner and fire a push 5 minutes before
  any entry starts.
* **Google Calendar** is a one-way mirror — the planner pushes to it
  on demand; we never read events back.
* **Notes** are freeform markdown that also live under a category.
* **Moments** sit outside the planning loop entirely — a place to
  pause when the loop itself is what's pulling at you.

The system optimises for one question per week: **are you giving each
life area the weight you actually want?**
