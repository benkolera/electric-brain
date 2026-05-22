// Sub-second countdown for the focus widget. The server is the
// authority on transitions — this hook only paints the visual
// remaining time based on `data-ends-at` (ISO 8601). The element's
// text is replaced every second; on hitting 00:00 we keep showing 00:00
// (the server will broadcast the transition shortly afterwards).

const FocusCountdown = {
  mounted() {
    this._tick = () => this.render()
    this.render()
    this._interval = setInterval(this._tick, 1000)
  },

  updated() {
    this.render()
  },

  destroyed() {
    if (this._interval) clearInterval(this._interval)
  },

  render() {
    const endsAt = this.el.dataset.endsAt
    if (!endsAt) return
    const remaining = Math.max(0, new Date(endsAt) - new Date())
    const totalSeconds = Math.floor(remaining / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    this.el.textContent = `${pad(minutes)}:${pad(seconds)}`
  },
}

function pad(n) {
  return n.toString().padStart(2, "0")
}

export default { FocusCountdown }
