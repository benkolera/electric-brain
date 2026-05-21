// Phx hook: an Excalidraw whiteboard inside a manually-managed overlay div.
// The block in the page flow shows static SVG previews (light + dark themes);
// clicking "Open" reveals a fullscreen overlay and lazily imports Excalidraw +
// React on first use. Closing the overlay serialises the scene plus two SVG
// renders (light and dark) into hidden inputs so the next form submit persists
// them.
//
// The React + Excalidraw bundle is heavy (~2MB gzipped) and most users will
// never open a sketch, so all of it sits in a separate esbuild chunk loaded on
// demand via dynamic import. The main app.js bundle stays small.
//
// We avoid the native <dialog> element because iOS Safari's interaction
// between dialog showModal and 100vh sizing leaves Excalidraw measuring 0px
// on first paint, after which it can disappear entirely.

const ExcalidrawEditor = {
  mounted() {
    const el = this.el

    const overlay = document.querySelector(el.dataset.overlay)
    const openBtn = document.querySelector(el.dataset.openButton)
    const closeBtn = document.querySelector(el.dataset.closeButton)
    const snapshotInput = document.querySelector(el.dataset.snapshotInput)
    const svgLightInput = document.querySelector(el.dataset.svgLightInput)
    const svgDarkInput = document.querySelector(el.dataset.svgDarkInput)
    const previewLight = document.querySelector(el.dataset.previewLight)
    const previewDark = document.querySelector(el.dataset.previewDark)

    let api = null
    let lib = null

    const parseInitial = () => {
      try {
        const v = JSON.parse(snapshotInput?.value || "null")
        if (!v || typeof v !== "object") return null
        if (Array.isArray(v)) return { elements: v }
        return v
      } catch (_) { return null }
    }

    const loadLib = async () => {
      if (lib) return lib
      const [excalidraw, react, reactDom] = await Promise.all([
        import("@excalidraw/excalidraw"),
        import("react"),
        import("react-dom/client"),
        import("@excalidraw/excalidraw/index.css"),
      ])
      // React + react-dom ship as CJS; dynamic import wraps named exports
      // under .default. Excalidraw is ESM. Fall back through both to stay safe.
      const reactNs = react.default || react
      const reactDomNs = reactDom.default || reactDom
      const excalidrawNs = excalidraw.default || excalidraw
      lib = {
        Excalidraw: excalidrawNs.Excalidraw || excalidraw.Excalidraw,
        exportToSvg: excalidrawNs.exportToSvg || excalidraw.exportToSvg,
        serializeAsJSON: excalidrawNs.serializeAsJSON || excalidraw.serializeAsJSON,
        createElement: reactNs.createElement,
        createRoot: reactDomNs.createRoot,
      }
      return lib
    }

    const mount = async () => {
      if (this._root) return
      const { Excalidraw, createElement, createRoot } = await loadLib()
      const initial = parseInitial()

      this._root = createRoot(el)
      this._root.render(
        createElement(Excalidraw, {
          initialData: initial,
          excalidrawAPI: (a) => { api = a },
        }),
      )
    }

    const renderSvg = async (elements, appState, files, dark) => {
      if (!elements.length) return ""
      const { exportToSvg } = lib
      const svgEl = await exportToSvg({
        elements,
        appState: { ...appState, exportBackground: false, exportWithDarkMode: dark },
        files,
        exportPadding: 16,
      })
      return new XMLSerializer().serializeToString(svgEl)
    }

    const captureAndSave = async () => {
      if (!api || !lib) return
      try {
        const elements = api.getSceneElements()
        const appState = api.getAppState()
        const files = api.getFiles()

        if (snapshotInput) {
          snapshotInput.value = lib.serializeAsJSON(elements, appState, files, "local")
        }

        const [lightSvg, darkSvg] = await Promise.all([
          renderSvg(elements, appState, files, false),
          renderSvg(elements, appState, files, true),
        ])

        if (svgLightInput) svgLightInput.value = lightSvg
        if (svgDarkInput) svgDarkInput.value = darkSvg
        if (previewLight) previewLight.innerHTML = lightSvg
        if (previewDark) previewDark.innerHTML = darkSvg || lightSvg

        el.dispatchEvent(new Event("dirty", { bubbles: true }))
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
        requestAnimationFrame(() => { mount() })
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
