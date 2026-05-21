// Phx hook: shows a banner whenever a form has unsaved input. The server
// renders the banner visible whenever it knows the form is dirty (after an
// add/remove/move action). For changes that don't hit the server — typing in
// a textarea, closing the Excalidraw modal — we listen for input events on
// the form and reveal the banner client-side.
//
// The banner is identified by a CSS selector in data-banner; the dirty class
// to remove is "hidden" (Tailwind).
//
// Other hooks (eg ExcalidrawEditor) can mark a form dirty by dispatching a
// bubbling "dirty" event from any element inside the form.

const DirtyForm = {
  mounted() {
    const form = this.el
    const bannerSel = form.dataset.banner
    const banner = bannerSel ? document.querySelector(bannerSel) : null

    if (!banner) return

    const show = () => banner.classList.remove("hidden")

    this._show = show
    form.addEventListener("input", show)
    form.addEventListener("dirty", show)
  },

  destroyed() {
    if (this._show) {
      this.el.removeEventListener("input", this._show)
      this.el.removeEventListener("dirty", this._show)
    }
  },
}

export default { DirtyForm }
