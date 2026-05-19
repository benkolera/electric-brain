// Touch-friendly drawing hooks. Strokes are stored as
//   { width, height, strokes: [{ color, size, points: [[x, y], ...] }] }
// and rendered to SVG so they scale with the container.

const NEON_BLUE = "#00F0FF"
const NEON_PURPLE = "#9D00FF"
const STROKE_WIDTH = 2.5

function makeSvg(width, height) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  svg.setAttribute("viewBox", `0 0 ${width} ${height}`)
  svg.setAttribute("preserveAspectRatio", "xMidYMid meet")
  svg.style.width = "100%"
  svg.style.height = "100%"
  svg.style.display = "block"
  return svg
}

function pointsToPath(points) {
  if (points.length === 0) return ""
  const [first, ...rest] = points
  return rest.reduce(
    (d, [x, y]) => `${d} L ${x.toFixed(2)} ${y.toFixed(2)}`,
    `M ${first[0].toFixed(2)} ${first[1].toFixed(2)}`,
  )
}

function renderStrokes(svg, strokes) {
  while (svg.firstChild) svg.removeChild(svg.firstChild)
  for (const stroke of strokes) {
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
    path.setAttribute("d", pointsToPath(stroke.points))
    path.setAttribute("fill", "none")
    path.setAttribute("stroke", stroke.color || NEON_BLUE)
    path.setAttribute("stroke-width", stroke.size || STROKE_WIDTH)
    path.setAttribute("stroke-linecap", "round")
    path.setAttribute("stroke-linejoin", "round")
    svg.appendChild(path)
  }
}

const DrawingCanvas = {
  mounted() {
    const el = this.el
    const targetSel = el.dataset.target
    const target = targetSel ? document.querySelector(targetSel) : null
    const rect = el.getBoundingClientRect()
    const width = Math.max(1, rect.width)
    const height = Math.max(1, rect.height)

    let initial = null
    try { initial = JSON.parse(el.dataset.initial || "null") } catch (_) {}

    this.state = {
      width: initial?.width || width,
      height: initial?.height || height,
      strokes: Array.isArray(initial?.strokes) ? initial.strokes : [],
    }
    this.current = null
    this.svg = makeSvg(this.state.width, this.state.height)
    el.appendChild(this.svg)
    renderStrokes(this.svg, this.state.strokes)

    const sync = () => {
      if (target) target.value = JSON.stringify(this.state)
    }
    sync()

    const localPoint = (e) => {
      const r = el.getBoundingClientRect()
      const scaleX = this.state.width / r.width
      const scaleY = this.state.height / r.height
      return [(e.clientX - r.left) * scaleX, (e.clientY - r.top) * scaleY]
    }

    const start = (e) => {
      if (e.button !== undefined && e.button !== 0) return
      e.preventDefault()
      el.setPointerCapture?.(e.pointerId)
      this.current = {
        color: e.shiftKey ? NEON_PURPLE : NEON_BLUE,
        size: STROKE_WIDTH,
        points: [localPoint(e)],
      }
      this.state.strokes.push(this.current)
      renderStrokes(this.svg, this.state.strokes)
    }

    const move = (e) => {
      if (!this.current) return
      e.preventDefault()
      this.current.points.push(localPoint(e))
      // Update only the last path for perf.
      const last = this.svg.lastChild
      if (last) last.setAttribute("d", pointsToPath(this.current.points))
    }

    const end = (e) => {
      if (!this.current) return
      e.preventDefault?.()
      el.releasePointerCapture?.(e.pointerId)
      this.current = null
      sync()
    }

    el.addEventListener("pointerdown", start)
    el.addEventListener("pointermove", move)
    el.addEventListener("pointerup", end)
    el.addEventListener("pointercancel", end)
    el.addEventListener("pointerleave", (e) => { if (this.current) end(e) })

    const clearBtn = document.getElementById("clear-canvas-btn")
    if (clearBtn) {
      this.clearHandler = () => {
        this.state.strokes = []
        renderStrokes(this.svg, this.state.strokes)
        sync()
      }
      clearBtn.addEventListener("click", this.clearHandler)
    }

    this._handlers = { start, move, end }
    this._sync = sync
  },
}

const DrawingView = {
  mounted() {
    const el = this.el
    let data = null
    try { data = JSON.parse(el.dataset.drawing || "null") } catch (_) {}
    if (!data || !Array.isArray(data.strokes)) return
    const svg = makeSvg(data.width || 600, data.height || 400)
    el.appendChild(svg)
    renderStrokes(svg, data.strokes)
  },
}

export default { DrawingCanvas, DrawingView }
