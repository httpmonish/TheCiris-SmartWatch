/* CIRIS Smartwatch PWA Service Worker (Offline-First Cache) */
const CACHE_NAME = 'ciris-v3.0.0';
const ASSETS_TO_CACHE = [
  '/',
  '/index.html',
  '/styles/tokens.css',
  '/styles/components.css',
  '/style.css',
  '/scrollytelling.js',
  '/telemetry.js',
  '/chatbot.js',
  '/ml_platform_ui.js',
  '/manifest.json'
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(ASSETS_TO_CACHE).catch(() => {});
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  // Pass-through for real-time telemetry API and SSE
  if (e.request.url.includes('/api/telemetry/stream') || e.request.url.includes('/api/telemetry/live')) {
    return;
  }
  e.respondWith(
    caches.match(e.request).then((res) => {
      return res || fetch(e.request).catch(() => caches.match('/index.html'));
    })
  );
});
