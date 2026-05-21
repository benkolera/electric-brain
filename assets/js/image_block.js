// Phx hook: an image block's file picker. The chosen image is downscaled to
// a max edge of 1600px and JPEG-encoded at 0.85 quality in the browser, then
// stored as a base64 data URL in the `[upload]` hidden input. On the next
// form submit the server decodes it, writes to ImageStore, and persists the
// resulting key (see Electricbrain.Notes.Images.put_from_data_url/2).
//
// The wrapper has phx-update="ignore", so any data URL written here survives
// LiveView patches and the user keeps their preview through reorder/add-block
// events.

const MAX_DIM = 1600
const JPEG_QUALITY = 0.85

const ImageBlock = {
  mounted() {
    const el = this.el
    const uploadInput = document.querySelector(el.dataset.uploadInput)
    const fileInput = document.querySelector(el.dataset.fileInput)
    const previewImg = document.querySelector(el.dataset.previewImg)
    const replaceLabel = document.querySelector(el.dataset.replaceLabel)

    if (!uploadInput || !fileInput) return

    const handler = async () => {
      const file = fileInput.files?.[0]
      if (!file) return
      try {
        const dataUrl = await downscaleToDataUrl(file)
        uploadInput.value = dataUrl
        uploadInput.dispatchEvent(new Event("input", { bubbles: true }))

        if (previewImg) {
          previewImg.src = dataUrl
          previewImg.classList.remove("hidden")
          const placeholder = document.getElementById(previewImg.id + "-placeholder")
          if (placeholder) placeholder.classList.add("hidden")
        }

        if (replaceLabel) {
          const text = replaceLabel.lastChild
          if (text && text.nodeType === Node.TEXT_NODE) {
            text.textContent = " Replace"
          }
        }
      } catch (e) {
        console.error("image block: downscale failed", e)
      }
    }

    fileInput.addEventListener("change", handler)
    this._handler = handler
    this._fileInput = fileInput
  },

  destroyed() {
    if (this._handler && this._fileInput) {
      this._fileInput.removeEventListener("change", this._handler)
    }
  },
}

async function downscaleToDataUrl(file) {
  const bitmap = await createImageBitmap(file).catch(() => null)
  let width, height, drawSource

  if (bitmap) {
    width = bitmap.width
    height = bitmap.height
    drawSource = bitmap
  } else {
    // Fallback path for browsers without createImageBitmap (rare).
    const img = await loadImageFromFile(file)
    width = img.naturalWidth
    height = img.naturalHeight
    drawSource = img
  }

  const scale = Math.min(1, MAX_DIM / Math.max(width, height))
  const w = Math.round(width * scale)
  const h = Math.round(height * scale)

  const canvas = document.createElement("canvas")
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext("2d")
  ctx.fillStyle = "#ffffff"
  ctx.fillRect(0, 0, w, h)
  ctx.drawImage(drawSource, 0, 0, w, h)

  // canvas.toDataURL is synchronous and gives a data URL directly; cheaper
  // than toBlob + FileReader and works in every browser we target.
  return canvas.toDataURL("image/jpeg", JPEG_QUALITY)
}

function loadImageFromFile(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(url)
      resolve(img)
    }
    img.onerror = (e) => {
      URL.revokeObjectURL(url)
      reject(e)
    }
    img.src = url
  })
}

export default { ImageBlock }
