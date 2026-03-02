// SVG icons are embedded in manifest, so no need to cache PNG files
const CACHE_NAME = 'bienestar-v5';
const ASSETS = [
    './',
    'index.html',
    'manifest.json',
    'style.css',
    'app.js',
    'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Outfit:wght@400;600;700&display=swap',
    'https://cdn.jsdelivr.net/npm/chart.js',
    'https://unpkg.com/lucide@latest'
];

self.addEventListener('install', (event) => {
    console.log('[SW] installing');
    // activate immediately
    self.skipWaiting();
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => {
            return cache.addAll(ASSETS);
        })
    );
});

self.addEventListener('activate', (event) => {
    console.log('[SW] activated');
    // take control of uncontrolled clients
    event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
    event.respondWith(
        caches.match(event.request).then((response) => {
            return response || fetch(event.request);
        })
    );
});
