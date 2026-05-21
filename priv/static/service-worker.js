// Minimal service worker for Electric Brain — just handles web push.
// Caching/offline support is not in scope for v1.

self.addEventListener('install', (event) => {
  // Activate immediately, don't wait for old tabs to close.
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim())
})

self.addEventListener('push', (event) => {
  // Payload arrives as JSON `{title, body, url}`. Fall back gracefully if
  // the server pushes a plain string or nothing.
  let title = 'Electric Brain'
  let body = ''
  let url = '/'

  if (event.data) {
    try {
      const data = event.data.json()
      title = data.title || title
      body = data.body || body
      url = data.url || url
    } catch (_) {
      body = event.data.text()
    }
  }

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: '/images/brain-logo-256.png',
      badge: '/images/brain-logo-256.png',
      data: { url },
      tag: 'electricbrain',
      renotify: false
    })
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const url = (event.notification.data && event.notification.data.url) || '/'

  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        // If we already have a window open, focus it and navigate.
        for (const client of clientList) {
          if ('focus' in client) {
            client.focus()
            if ('navigate' in client) client.navigate(url)
            return
          }
        }
        if (self.clients.openWindow) return self.clients.openWindow(url)
      })
  )
})
