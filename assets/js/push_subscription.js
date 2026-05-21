// LiveView hook that wires the browser's PushManager into the Settings
// page. Triggered by a server `enable_push` event when the user clicks
// "Enable notifications" — the hook requests permission, subscribes to
// push via the service worker, and pushes the subscription up to the
// server. Tearing down is the inverse via `disable_push`.
//
// The hook element carries `data-vapid-public-key` (URL-safe base64).

const urlBase64ToUint8Array = (base64) => {
  const padding = '='.repeat((4 - (base64.length % 4)) % 4)
  const normalized = (base64 + padding).replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(normalized)
  const out = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i += 1) out[i] = raw.charCodeAt(i)
  return out
}

const arrayBufferToBase64 = (buffer) => {
  const bytes = new Uint8Array(buffer)
  let bin = ''
  for (let i = 0; i < bytes.length; i += 1) bin += String.fromCharCode(bytes[i])
  return btoa(bin)
}

const subscribeToPush = async (vapidPublicKey) => {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
    throw new Error('Push notifications are not supported in this browser.')
  }

  const permission = await Notification.requestPermission()
  if (permission !== 'granted') {
    throw new Error('Notification permission was not granted.')
  }

  const registration =
    (await navigator.serviceWorker.getRegistration('/service-worker.js')) ||
    (await navigator.serviceWorker.register('/service-worker.js'))

  // Wait for the service worker to become active so PushManager has
  // something to subscribe against.
  await navigator.serviceWorker.ready

  const existing = await registration.pushManager.getSubscription()
  if (existing) return existing

  return registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(vapidPublicKey)
  })
}

const PushSubscription = {
  mounted() {
    this.handleEvent('push:request_subscribe', async () => {
      try {
        const vapid = this.el.dataset.vapidPublicKey
        if (!vapid) throw new Error('VAPID public key not configured on this server.')

        const subscription = await subscribeToPush(vapid)
        const json = subscription.toJSON()

        this.pushEvent('save_push_subscription', {
          endpoint: subscription.endpoint,
          p256dh_key: json.keys.p256dh,
          auth_key: json.keys.auth,
          user_agent: navigator.userAgent
        })
      } catch (err) {
        this.pushEvent('push_subscribe_failed', { message: err.message })
      }
    })

    this.handleEvent('push:request_unsubscribe', async () => {
      try {
        const registration =
          await navigator.serviceWorker.getRegistration('/service-worker.js')
        if (!registration) return
        const sub = await registration.pushManager.getSubscription()
        if (sub) await sub.unsubscribe()
      } catch (err) {
        this.pushEvent('push_subscribe_failed', { message: err.message })
      }
    })
  }
}

export default PushSubscription
