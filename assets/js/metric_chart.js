// Chart.js line chart for a single Metric. The LiveView injects:
//
//   {label, unit, aggregation, period, timezone, points, goal}
//
// `points` is already bucketed server-side (`Electricbrain.Metrics.Chart`)
// — each entry is `{t: iso8601, v: number}` and is plotted as-is. When
// `goal` is set (`{kind: "at_least"|"at_most", value: number}`), we
// overlay a horizontal "yellow brick road" line at `goal.value`.
import { Chart, registerables } from 'chart.js'
import 'chartjs-adapter-date-fns'

Chart.register(...registerables)

const toPlotPoints = (points) =>
  points
    .map((p) => ({ x: new Date(p.t), y: p.v }))
    .sort((a, b) => a.x - b.x)

const periodTimeUnit = (period) => {
  switch (period) {
    case 'week': return 'week'
    case 'month': return 'month'
    default: return 'day'
  }
}

const goalDataset = (goal, points) => {
  if (!goal || points.length === 0) return null

  // Flat road: same y at every x in the visible range, plus a small
  // forward extension so it always reaches the right edge of the chart.
  const xs = points.map((p) => p.x.getTime())
  const min = new Date(Math.min(...xs))
  const max = new Date(Math.max(...xs) + 24 * 60 * 60 * 1000)

  return {
    label: `Goal (${goal.kind === 'at_least' ? '≥' : '≤'} ${goal.value})`,
    data: [
      { x: min, y: goal.value },
      { x: max, y: goal.value }
    ],
    borderColor: '#facc15',
    borderDash: [6, 4],
    borderWidth: 2,
    pointRadius: 0,
    fill: false,
    tension: 0
  }
}

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
    const data = toPlotPoints(cfg.points)

    this.el.replaceChildren()
    const canvas = document.createElement('canvas')
    this.el.appendChild(canvas)

    const datasets = [
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

    const road = goalDataset(cfg.goal, data)
    if (road) datasets.push(road)

    this.chart = new Chart(canvas, {
      type: 'line',
      data: { datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: {
            type: 'time',
            time: { unit: periodTimeUnit(cfg.period) },
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
