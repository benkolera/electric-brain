// Phx hook: an Excalidraw whiteboard inside a manually-managed overlay div.
// The block in the page flow shows a static SVG preview; clicking "Open"
// reveals a fullscreen overlay and lazily mounts React + Excalidraw. Closing
// the overlay serialises the scene and a fresh SVG export into hidden inputs
// so the next form submit persists them.
//
// We avoid the native <dialog> element because iOS Safari's interaction
// between dialog showModal and 100vh sizing leaves Excalidraw measuring 0px
// on first paint, after which it can disappear entirely.

import "@excalidraw/excalidraw/index.css"
import { createElement } from "react"
import { createRoot } from "react-dom/client"
import { Excalidraw, exportToSvg, serializeAsJSON } from "@excalidraw/excalidraw"

const ExcalidrawEditor = {
  mounted() {
    const el = this.el

    const overlay = document.querySelector(el.dataset.overlay)
    const openBtn = document.querySelector(el.dataset.openButton)
    const closeBtn = document.querySelector(el.dataset.closeButton)
    const snapshotInput = document.querySelector(el.dataset.snapshotInput)
    const svgInput = document.querySelector(el.dataset.svgInput)
    const preview = document.querySelector(el.dataset.preview)

    let api = null
    let root = null

    const parseInitial = () => {
      try {
        const v = JSON.parse(snapshotInput?.value || "null")
        if (!v || typeof v !== "object") return null
        // Excalidraw scenes are serialised as { type, version, elements, appState, files }.
        // Accept either the raw serialised string form or just the elements array.
        if (Array.isArray(v)) return { elements: v }
        return v
      } catch (_) { return null }
    }

    const mount = () => {
      if (root) return
      const initial = parseInitial()

      root = createRoot(el)
      root.render(
        createElement(Excalidraw, {
          initialData: initial,
          excalidrawAPI: (a) => { api = a },
        }),
      )
      this._root = root
    }

    const captureAndSave = async () => {
      if (!api) return
      try {
        const elements = api.getSceneElements()
        const appState = api.getAppState()
        const files = api.getFiles()

        if (snapshotInput) {
          snapshotInput.value = serializeAsJSON(elements, appState, files, "local")
        }

        let svg = ""
        if (elements.length > 0) {
          const svgEl = await exportToSvg({
            elements,
            appState: { ...appState, exportBackground: false, exportWithDarkMode: false },
            files,
            exportPadding: 16,
          })
          svg = new XMLSerializer().serializeToString(svgEl)
        }
        if (svgInput) svgInput.value = svg
        if (preview) preview.innerHTML = svg
      } catch (e) {
        console.error("excalidraw save failed", e)
      }
    }

    if (openBtn && overlay) {
      this._open = (e) => {
        e?.preventDefault()
        overlay.style.display = "flex"
        // Wait a frame so the overlay has measurable dimensions before
        // Excalidraw mounts and reads its bounding rect.
        requestAnimationFrame(() => mount())
      }
      openBtn.addEventListener("click", this._open)
    }

    if (closeBtn && overlay) {
      this._close = async (e) => {
        e?.preventDefault()
        await captureAndSave()
        overlay.style.display = "none"
      }
      closeBtn.addEventListener("click", this._close)
    }

    this._refs = { overlay, openBtn, closeBtn }
  },

  destroyed() {
    const { openBtn, closeBtn } = this._refs || {}
    if (openBtn && this._open) openBtn.removeEventListener("click", this._open)
    if (closeBtn && this._close) closeBtn.removeEventListener("click", this._close)
    if (this._root) this._root.unmount()
  },
}

export default { ExcalidrawEditor }
