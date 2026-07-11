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

## Meals — ingredient library

The `/ingredients` page is the foundation of meal planning: a library
of foods with **per-100g macros** (kcal, protein, fat, carbs, fibre).
Recipes are built from these ingredients, so their macros are
calculated for you — the more the library grows, the less typing a
new recipe takes.

Two kinds of ingredient share the library:

* **AFCD** — 1,588 whole foods seeded from the Australian Food
  Composition Database (Release 3). These are read-only reference
  data; search for "chicken breast", "rolled oats", "broccoli" and
  they're already there.
* **Custom** — your own entries, typed in from a packet label. Use
  these for branded products (protein powder, Greek yogurt, wraps)
  the AFCD doesn't carry. Only you can see, edit, or delete them.

The library is search-first — a blank search shows just your custom
entries; type to search everything.

Ingredient data derived from the Australian Food Composition
Database © Food Standards Australia New Zealand, CC-BY 4.0.

## Meals — recipes

A **recipe** on `/recipes` is a dish built from ingredient lines
(grams of an ingredient) plus how many **servings** the batch makes.
Per-serving macros are calculated from the lines — you never type
recipe macros by hand, and they stay correct when you tweak
quantities.

Each recipe has a **slot**, which is where the weekly plan may place
it:

* **Breakfast** — the plan picks two per week
* **Main** — lunch and dinner; the plan picks two and alternates them
* **Snack** — one per week, eaten daily
* **Shake** — protein top-ups the plan adds when a day's protein
  falls short of target

That 2 + 2 + 1 structure (from *The Bodybuilder's Meal Prep
Cookbook*) is deliberate: enough variety to not get bored, few enough
dishes that Sunday prep stays a two-pot job.

## Meals — targets

`/meals/settings` holds your **nutrition profile** — the inputs the
weekly plan's calorie and macro targets are computed from:

1. **BMR** via Mifflin-St Jeor (height, birthdate, sex, and your
   latest weight)
2. **TDEE** = BMR × an activity multiplier (sedentary → very active)
3. **Goal target** = TDEE ± your cut/bulk rate (kcal per day)
4. **Macro split**: protein by bodyweight (g/kg, default 2.0), fat as
   a percentage of calories (default 25%), carbs get the remainder

Weight isn't typed in here — link your **weight metric** (the same
series the Metrics page charts) and the latest reading feeds the
math. The panel also shows last week's weight change, which is the
feedback loop: cutting but the scale isn't moving → drop the target;
losing too fast → raise it.

Every target field has a **manual override** — leave blank for
computed, fill in to pin that number. If you don't want the BMR model
at all, set all four overrides and skip the body inputs entirely.

Meal times (breakfast, shake, lunch, snack, dinner) and the Saturday
shopping / Sunday prep reminder times also live here — the meal
scheduler fires reminders at these times in your local timezone.

## Meals — the weekly plan

`/meals` shows one week (Mon–Fri) as a grid of five daily slots:
breakfast, shake, lunch, snack, dinner. From Saturday the page
defaults to the **upcoming** week — Saturday shop and Sunday prep
serve the week ahead.

**Generate** builds the week automatically:

1. Picks 2 breakfasts, 2 mains, 1 snack, and 1 shake from your
   recipes — rotating week to week and avoiding last week's picks
   when the library is big enough
2. Alternates them across the days (Mon/Wed/Fri vs Tue/Thu, mains
   swapping between lunch and dinner)
3. Scales each recipe's servings so days land on your calorie
   target, in practical quarter-serving steps
4. Adds shakes wherever a day's protein falls short, up to your
   max-shakes-per-day
5. Flags anything it couldn't reach as warnings on the plan

The generated week is a **draft**: swap any cell to a different
recipe, adjust servings, regenerate entirely, and watch the per-day
totals against your targets. Targets are snapshotted at generation,
so later profile tweaks don't shift a planned week.

**Confirm** locks the week in. That's the Saturday moment: confirm,
then shop.

## Meals — shopping list

Confirming a week builds its **shopping list** at
`/meals/shopping`: every ingredient across the week's meals,
aggregated into one line each (recipe quantities × planned servings ÷
batch size). Check items off as they go in the trolley — the state
persists, so closing the phone mid-shop loses nothing.

If the plan changes after confirming, the list rebuilds with updated
quantities while keeping what you've already checked; ingredients
that dropped out of the plan disappear from the list.

## Meals — reminders

With push notifications enabled (see Notifications), the meal
scheduler sends:

* **Meal-time nudges** — "Lunch — Chicken rice · 1.5 servings" a few
  minutes before each confirmed meal's slot time
* **Saturday shopping** — "list ready" at your shopping reminder
  time once next week is confirmed; if you haven't planned yet, a
  nudge to generate the week instead (once per Saturday)
* **Sunday prep** — the week's dishes at your prep reminder time

All times are yours to set on the meal settings page, and fire in
your local timezone.

## Meals — is it working?

The point of the plan is the trend, not the week. On meal settings,
pick your **progress metrics** — weight, waist, body fat %, key
lifts, any Metrics series — and the meal plan page shows each one's
latest value and week-over-week change beside the plan.

Direction colouring follows the metric's goal: an `at_most` goal
(waist, body fat) colours a falling week green; an `at_least` goal
(lifts, weight on a bulk) colours a rising week green. Record the
measurements however you already do — manually on the Metrics page,
at habit completion, or via a connected device.

## Meals — Oura ring

Connect your Oura ring on the meal settings page and every morning
Trellis pulls your daily calorie burn into two metrics ("Oura active
kcal" and "Oura total kcal") that chart like any other series.

The bigger payoff is **adaptive TDEE**: once a week of data exists,
your calorie target switches from the textbook
`BMR × activity multiplier` estimate to your **measured 14-day
average burn** — the targets panel notes which basis is in effect.
With an observed TDEE the height/birthdate/sex inputs become
optional; only weight is still needed for the protein split.

Oura retired personal access tokens, so this uses OAuth — the server
needs `OURA_CLIENT_ID`/`OURA_CLIENT_SECRET` configured (register an
app at cloud.ouraring.com); the card hides itself otherwise.

## Meals — Hume scale (measurement ingest)

The Hume Body Pod has no public API, but it syncs to Apple Health —
and anything in Apple Health can be relayed to Trellis:

1. On meal settings, map your **weight** and **body fat** metrics and
   generate an **ingest token** (shown once — copy it immediately)
2. Install the **Health Auto Export** iOS app
3. Add a REST API automation: URL
   `https://<your-trellis>/api/ingest/measurements`, method POST,
   header `Authorization: Bearer <token>`, metrics *Weight/Body Mass*
   and *Body Fat Percentage*, on a daily schedule

Readings land as ordinary Measurements on the mapped metrics —
feeding the BMR, the weekly delta, and the progress panel. Posts are
idempotent (a re-sent reading is skipped), and the endpoint also
accepts a plain JSON shape for any other relay:

    {"measurements": [{"metric": "weight", "value": 82.5,
                       "recorded_at": "2026-07-11T07:12:00Z"}]}

Revoke a token any time by generating a new one and deleting the old
pairing.

## Training — linear A/B strength

`/training` runs a simple linear programme over your exercise pool:
two alternating session templates (classic **A**: squat, bench, row;
**B**: squat, press, deadlift 1×5), each ending with accessory slots
that rotate through the kettlebell/bodyweight pool.

**Progression is automatic:**

* Barbell lifts: hit every set → next session adds the increment
  (+2.5 kg, +5 kg deadlift). Miss (or skip) any set → the weight
  repeats; after 3 consecutive misses the lift deloads ~10%, rounded
  to 2.5 kg, and you build back up.
* Accessories: hit every set → next time one more rep, up to the
  ceiling. Kettlebells then jump to the next bell and reps reset;
  pull ups and dips just keep climbing.

**In the gym** (`/training/session`): tap a set to log it at target
reps; tap − if you got fewer; tap again to unlog. A rest countdown
runs between sets. **Finish** applies progression and logs each
lift's top set and estimated 1RM (Epley) into Metrics — chart them,
or pin them on the meals progress panel. **Abandon** applies nothing
and the same session is prescribed next time. Finishing with unlogged
sets counts them as misses — deliberate: half a session is a stall.

Prescriptions are working sets only — warm-ups are yours, unlogged.
Single-arm KB movements count target reps per arm. All weights kg.

**Settings** (`/training/settings`): training days + reminder time,
rest seconds, per-exercise current weight/reps (set your REAL
working weights before the first session — defaults start near the
bar) and progression parameters, plus the template editor. Editing a
weight resets that lift's stall count.

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

## Notes — block-composed freeform pages

A **note** has a title and an ordered list of **blocks**. Block
kinds today:

* **Markdown** — write in markdown; the show page renders it.
* **Sketch** — a full Excalidraw whiteboard. Tap **Open editor**
  to pop a fullscreen canvas; draw, diagram, write with an Apple
  Pencil, then tap **Done** to capture a preview back into the
  note. The note page shows the still preview; opening the block
  again gives you the full editor with pan/zoom.
* **Image** — pick a photo or screenshot; the browser downscales
  it (max 1600px, JPEG q=0.85) and embeds it inline in the note.
  Add alt text in the field below the preview.

In the editor, each block has up/down arrows to reorder and a
trash button to remove it. The buttons below the list add a new
block of either kind to the end. The plan is to grow more block
kinds (images, embeds, checklists) over time — the data model
already supports it.

The list view previews the first markdown block of each note. If
a note has no markdown, it shows "(sketch)" or nothing.

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

## Focus — pomodoro timer

The floating **Focus** pill (bottom-left on every page) starts a
pomodoro session. Default 25 minutes work + 5 minutes break;
adjust the per-session values in the start dialog, or change your
defaults under Settings → Focus.

A session can optionally be *aimed* at one of:

* a **todo** (lights up in history under that todo's name),
* a **habit**,
* a **time block** (e.g. focusing during a Work block),
* a **category** (broader than any one item).

Pick "Nothing" for a freestanding session — just "I'm focusing for
25 minutes". The DB lets each session target at most one of those
four, so the planner stays the place where things are co-located
across categories.

Sessions are server-backed, so the widget is in sync across every
device you're signed into. On the planner, each scheduled entry's
expanded panel has a "Focus" button that starts a session aimed at
that entry — one tap, no dialog.

End-of-work and end-of-break fire a push notification (same
mechanism as planner reminders — enable in Settings → Notifications).

History lives at `/focus`: today's tally up top, then completed and
abandoned sessions grouped by day. Active sessions only show in the
floating widget, not in history.

## Notifications

Settings → Notifications → Enable on this device, per browser.
Five minutes before each planned item starts, you get a push.

On iPhone you must install the app to the home screen first —
share → Add to Home Screen → open the installed icon → then Enable.
Safari tabs don't get web push.

## Even Hub (G2 glasses)

If you wear Even Realities G2 smart glasses, the Trellis **Even Hub
plugin** surfaces three things on the HUD:

* **Now / Next** — the planner entry happening now plus the one
  coming up, with minutes remaining / until.
* **Live focus countdown** — when a focus session is running, large
  mm:ss for work and break.
* **Today's habits** — daily-period habits, plus any week/month
  habits still owed.

**Pairing.** Settings → Even Hub glasses → Pair Even Hub plugin.
A 6-character code appears (valid for 10 minutes). Open the Trellis
plugin in your Even Hub and type the code; it exchanges the code for
a long-lived token stored on the plugin. Unpair from the same Settings
card any time.

The plugin polls every 10–30 seconds, so the HUD lags real-time by
about that much. Trellis only ever stores a hash of the pairing token
— the cleartext is shown to the plugin exactly once during pairing.

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
* **Notes** are freeform pages composed of typed blocks (markdown,
  sketch, more later).
* **Moments** sit outside the planning loop entirely — a place to
  pause when the loop itself is what's pulling at you.

The system optimises for one question per week: **are you giving each
life area the weight you actually want?**
