// Service worker: makes the app work offline and delivers updates.
// A new VERSION creates a new cache; the page shows "update available" and the
// user decides when to switch, so nothing reloads in the middle of typing.
const VERSION = '1.3.0';
const CACHE = `spending-app-${VERSION}`;
const ASSETS = [
  './',
  'index.html',
  'css/styles.css',
  'js/app.js',
  'js/logic.js',
  'js/db.js',
  'js/crypto.js',
  'js/sync.js',
  'js/config.js',
  'js/version.js',
  'manifest.webmanifest',
  'icons/icon.svg',
  'icons/icon-192.png',
  'icons/icon-512.png',
  'icons/apple-touch-icon.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    // `?v=` bypasses CDN caches, so an update never mixes files from two versions.
    caches.open(CACHE).then((cache) => Promise.all(ASSETS.map(async (url) => {
      const res = await fetch(`${url}?v=${VERSION}`, { cache: 'reload' });
      if (!res.ok) throw new Error(`${url}: ${res.status}`);
      await cache.put(url, res);
    }))),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter((k) => k.startsWith('spending-app-') && k !== CACHE).map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('message', (event) => {
  if (event.data?.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== self.location.origin) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    // Navigations (including ?amount=… links) always get the cached app shell.
    if (req.mode === 'navigate') {
      return (await cache.match('index.html')) || fetch(req);
    }
    return (await cache.match(req, { ignoreSearch: true })) || fetch(req);
  })());
});
