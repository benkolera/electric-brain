// Phx hook that mounts tldraw in a <dialog> modal. The block in the page
// flow shows a static SVG preview; clicking "Open" pops the dialog, the
// React + Tldraw root mounts lazily, and closing the dialog serialises the
// snapshot and a fresh SVG into hidden inputs so the next form submit
// persists them.

import "tldraw/tldraw.css"
import { createElement } from "react"
import { createRoot } from "react-dom/client"
import { Tldraw, getSnapshot, loadSnapshot } from "tldraw"

const TldrawEditor = {
  mounted() {
    const el = this.el

    const dialog = document.querySelector(el.dataset.dialog)
    const openBtn = document.querySelector(el.dataset.openButton)
    const closeBtn = document.querySelector(el.dataset.closeButton)
    const snapshotInput = document.querySelector(el.dataset.snapshotInput)
    const svgInput = document.querySelector(el.dataset.svgInput)
    const preview = document.querySelector(el.dataset.preview)

    let editor = null
    let root = null

    const parseInitial = () => {
      try {
        const v = JSON.parse(snapshotInput?.value || "null")
        return v && typeof v === "object" && Object.keys(v).length ? v : null
      } catch (_) {
        return null
      }
    }

    const mount = () => {
      if (root) return
      const initial = parseInitial()
      root = createRoot(el)
      root.render(
        createElement(Tldraw, {
          onMount: (ed) => {
            editor = ed
            if (initial) {
              try { loadSnapshot(ed.store, initial) } catch (e) { console.warn("tldraw loadSnapshot failed", e) }
            }
          },
        }),
      )
    }

    const captureAndSave = async () => {
      if (!editor) return
      try {
        if (snapshotInput) snapshotInput.value = JSON.stringify(getSnapshot(editor.store))

        const shapeIds = Array.from(editor.getCurrentPageShapeIds())
        let svg = ""
        if (shapeIds.length > 0) {
          const result = await editor.getSvgString(shapeIds, { background: false, padding: 16 })
          if (result?.svg) svg = result.svg
        }
        if (svgInput) svgInput.value = svg
        if (preview) preview.innerHTML = svg || preview.dataset.emptyHtml || ""
      } catch (e) {
        console.error("tldraw save failed", e)
      }
    }

    if (openBtn && dialog) {
      this._open = (e) => {
        e?.preventDefault()
        dialog.showModal()
        mount()
      }
      openBtn.addEventListener("click", this._open)
    }

    if (closeBtn && dialog) {
      this._close = async (e) => {
        e?.preventDefault()
        await captureAndSave()
        dialog.close()
      }
      closeBtn.addEventListener("click", this._close)
    }

    if (dialog) {
      this._cancel = async (e) => {
        // Escape / backdrop dismiss — still capture state.
        e.preventDefault()
        await captureAndSave()
        dialog.close()
      }
      dialog.addEventListener("cancel", this._cancel)
    }

    this._refs = { dialog, openBtn, closeBtn }
  },

  destroyed() {
    const { dialog, openBtn, closeBtn } = this._refs || {}
    if (openBtn && this._open) openBtn.removeEventListener("click", this._open)
    if (closeBtn && this._close) closeBtn.removeEventListener("click", this._close)
    if (dialog && this._cancel) dialog.removeEventListener("cancel", this._cancel)
    if (this._root) this._root.unmount()
  },
}

export default { TldrawEditor }
