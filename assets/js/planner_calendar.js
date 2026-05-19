// Must come before @schedule-x/* imports — Schedule-X references the global
// Temporal at module init time.
import 'temporal-polyfill/global'
import { createCalendar, createViewWeek } from '@schedule-x/calendar'
import { createDragAndDropPlugin } from '@schedule-x/drag-and-drop'
import '@schedule-x/theme-default/dist/index.css'

const toZdt = (iso, timezone) =>
  Temporal.Instant.from(iso).toZonedDateTimeISO(timezone)

const PlannerCalendar = {
  mounted() {
    this.timezone = this.el.dataset.timezone || 'UTC'
    const initialDate = this.el.dataset.weekStart // YYYY-MM-DD

    this.calendar = createCalendar(
      {
        views: [createViewWeek()],
        defaultView: 'week',
        isDark: true,
        timezone: this.timezone,
        weekOptions: { gridHeight: 700 },
        events: this.readEvents(),
        callbacks: {
          onEventUpdate: (event) => {
            this.pushEvent('entry_rescheduled', {
              id: event.id,
              start: event.start.toString(),
              end: event.end.toString()
            })
          },
          onEventClick: (event) => {
            this.pushEvent('entry_clicked', { id: event.id })
          },
          onClickDateTime: (zdt) => {
            this.pushEvent('slot_clicked', { instant: zdt.toInstant().toString() })
          }
        }
      },
      [createDragAndDropPlugin(15)]
    )

    this.calendar.render(this.el)

    this.handleEvent('planner:events', ({ events }) => {
      this.calendar.events.set(this.parseEvents(events))
    })

    this.handleEvent('planner:set_date', ({ date }) => {
      this.calendar.setView('week', Temporal.PlainDate.from(date))
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
    if (this.calendar) {
      // Schedule-X currently has no public destroy; rely on phx-update="ignore"
      this.calendar = null
    }
  }
}

export default PlannerCalendar
