// Must come before @schedule-x/* imports — Schedule-X references the global
// Temporal at module init time.
import 'temporal-polyfill/global'
import { createCalendar, createViewWeek } from '@schedule-x/calendar'
import { createDragAndDropPlugin } from '@schedule-x/drag-and-drop'
import { createResizePlugin } from '@schedule-x/resize'
import '@schedule-x/theme-default/dist/index.css'

const toZdt = (iso, timezone) =>
  Temporal.Instant.from(iso).toZonedDateTimeISO(timezone)

// Multi-day entries are split into one event per local day; the synthetic id
// looks like `<uuid>__chunk__<index>`. Server only knows the uuid.
const stripChunkSuffix = (id) => String(id).split('__chunk__')[0]

// Google Calendar's fixed 11-color event palette, mirrored on the server in
// Electricbrain.Categories.Colors so both views render the same color.
// Event payloads set `calendarId` to one of these names; Schedule-X looks
// the calendar up in its registered `calendars` config to apply the color.
const PALETTE = {
  lavender:  '#7986cb',
  sage:      '#33b679',
  grape:     '#8e24aa',
  flamingo:  '#e67c73',
  banana:    '#f6c026',
  tangerine: '#f5511d',
  peacock:   '#039be5',
  graphite:  '#616161',
  blueberry: '#3f51b5',
  basil:     '#0b8043',
  tomato:    '#d60000'
}

const CALENDARS = Object.fromEntries(
  Object.entries(PALETTE).map(([name, hex]) => [name, {
    colorName: name,
    lightColors: { main: hex, container: hex + '33', onContainer: '#000' },
    darkColors:  { main: hex, container: hex + '66', onContainer: '#fff' }
  }])
)

// Pick dark/light from the user's resolved theme. Explicit data-theme wins;
// otherwise fall back to the OS preference (the same source daisyUI is using).
function detectIsDark() {
  const explicit = document.documentElement.dataset.theme
  if (explicit === 'electricbrain-dark') return true
  if (explicit === 'electricbrain-light') return false
  return window.matchMedia('(prefers-color-scheme: dark)').matches
}

const PlannerCalendar = {
  mounted() {
    this.timezone = this.el.dataset.timezone || 'UTC'
    const initialDate = this.el.dataset.weekStart // YYYY-MM-DD

    this.calendar = createCalendar(
      {
        views: [createViewWeek()],
        defaultView: 'week',
        isDark: detectIsDark(),
        timezone: this.timezone,
        weekOptions: { gridHeight: 700 },
        calendars: CALENDARS,
        events: this.readEvents(),
        callbacks: {
          onEventUpdate: (event) => {
            this.pushEvent('entry_rescheduled', {
              id: stripChunkSuffix(event.id),
              start: event.start.toString(),
              end: event.end.toString()
            })
          },
          onEventClick: (event) => {
            this.pushEvent('entry_clicked', { id: stripChunkSuffix(event.id) })
          },
          onClickDateTime: (zdt) => {
            this.pushEvent('slot_clicked', { instant: zdt.toInstant().toString() })
          }
        }
      },
      [createDragAndDropPlugin(15), createResizePlugin(15)]
    )

    this.calendar.render(this.el)

    this.handleEvent('planner:events', ({ events }) => {
      this.calendar.events.set(this.parseEvents(events))
    })

    this.handleEvent('planner:set_date', ({ date }) => {
      this.calendar.setView('week', Temporal.PlainDate.from(date))
    })

    // Re-sync the calendar theme whenever the resolved theme could change:
    //   - OS preference flips (sunrise/sunset auto-switch)
    //   - User toggles theme in Settings (mutates <html data-theme>)
    // The calendar element uses phx-update="ignore", so we update via setTheme.
    this.applyTheme = () => {
      this.calendar.setTheme(detectIsDark() ? 'dark' : 'light')
    }

    this.mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
    this.mediaQuery.addEventListener('change', this.applyTheme)

    this.themeObserver = new MutationObserver(this.applyTheme)
    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['data-theme']
    })
  },

  readEvents() {
    const raw = this.el.dataset.events
    if (!raw) return []
    try {
      return this.parseEvents(JSON.parse(raw))
    } catch (e) {
      console.error('PlannerCalendar: bad events JSON', e)
      return []
    }
  },

  parseEvents(events) {
    return events.map((e) => ({
      ...e,
      start: toZdt(e.start, this.timezone),
      end: toZdt(e.end, this.timezone)
    }))
  },

  destroyed() {
    if (this.mediaQuery && this.applyTheme) {
      this.mediaQuery.removeEventListener('change', this.applyTheme)
    }
    if (this.themeObserver) {
      this.themeObserver.disconnect()
    }
    if (this.calendar) {
      // Schedule-X currently has no public destroy; rely on phx-update="ignore"
      this.calendar = null
    }
  }
}

export default PlannerCalendar
