// Chart.js line chart for a single Metric. The LiveView injects the data
// as `data-chart` JSON: `{label, unit, aggregation, timezone, points}`,
// where each point is `{t: iso8601, v: number}`. For :sum metrics we
// bucket points into daily totals; for :point we plot raw values.
import { Chart, registerables } from 'chart.js'
import 'chartjs-adapter-date-fns'

Chart.register(...registerables)

const dayKey = (iso) => {
  // Bucket by UTC date; the timezone-aware bucketing happens server-side
  // for the cases that need it (Phase 3). Sufficient for v1 single-user app.
  const d = new Date(iso)
  d.setUTCHours(0, 0, 0, 0)
  return d.toISOString()
}

const bucketSum = (points) => {
  const buckets = new Map()
  for (const p of points) {
    const key = dayKey(p.t)
    buckets.set(key, (buckets.get(key) || 0) + p.v)
  }
  return Array.from(buckets, ([t, v]) => ({ x: new Date(t), y: v }))
    .sort((a, b) => a.x - b.x)
}

const rawPoints = (points) =>
  points
    .map((p) => ({ x: new Date(p.t), y: p.v }))
    .sort((a, b) => a.x - b.x)

const MetricChart = {
  mounted() {
    this.render()
  },

  updated() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
    this.render()
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  },

  render() {
    const cfg = JSON.parse(this.el.dataset.chart)
    const data =
      cfg.aggregation === 'sum' ? bucketSum(cfg.points) : rawPoints(cfg.points)

    // Clear any previous canvas (phx-update="ignore" stops LV from doing it)
    this.el.replaceChildren()
    const canvas = document.createElement('canvas')
    this.el.appendChild(canvas)

    this.chart = new Chart(canvas, {
      type: 'line',
      data: {
        datasets: [
          {
            label: `${cfg.label} (${cfg.unit})`,
            data,
            borderColor: '#22d3ee',
            backgroundColor: 'rgba(34, 211, 238, 0.15)',
            tension: 0.2,
            pointRadius: 3,
            fill: cfg.aggregation === 'sum'
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: {
            type: 'time',
            time: { unit: 'day' },
            ticks: { color: '#94a3b8' },
            grid: { color: 'rgba(148, 163, 184, 0.1)' }
          },
          y: {
            ticks: { color: '#94a3b8' },
            grid: { color: 'rgba(148, 163, 184, 0.1)' }
          }
        },
        plugins: {
          legend: { labels: { color: '#cbd5e1' } }
        }
      }
    })
  }
}

export default MetricChart
