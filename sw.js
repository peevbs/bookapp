// App shell: network first, so a new version arrives on the next start; the cache is the offline fallback.
// vendor/ (OCR, barcode, Excel): cache first. These files never change, and after the first download
// they must work without internet. They are fetched in the background after install, so OCR and the
// barcode reader work offline even before they were used once.
// API calls go to other origins and are never touched here.
const V = 'raft-v33';
const VENDOR = 'raft-vendor-v1';
const SHELL = ['./', 'index.html', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png', 'icon-maskable-512.png'];
const VENDOR_FILES = [
  'vendor/zxing.min.js', 'vendor/xlsx.full.min.js', 'vendor/tesseract.min.js', 'vendor/worker.min.js',
  // tesseract picks one of the three cores by what the phone supports; new Chrome uses relaxed SIMD
  'vendor/core/tesseract-core-relaxedsimd-lstm.wasm.js', 'vendor/core/tesseract-core-simd-lstm.wasm.js', 'vendor/core/tesseract-core-lstm.wasm.js',
  'vendor/tessdata/bul.traineddata.gz', 'vendor/tessdata/eng.traineddata.gz',
  'vendor/fonts/cormorant-garamond-cyrillic-600-normal.woff2', 'vendor/fonts/cormorant-garamond-latin-600-normal.woff2',
  'vendor/fonts/cormorant-garamond-cyrillic-600-italic.woff2', 'vendor/fonts/cormorant-garamond-latin-600-italic.woff2'
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(V).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

async function prefetchVendor() {
  const c = await caches.open(VENDOR);
  for (const f of VENDOR_FILES) {
    try {
      if (await c.match(f)) continue;
      const r = await fetch(f);
      if (r.ok) await c.put(f, r);
    } catch (err) { /* no connection now: the file is cached the first time it is used */ }
  }
}

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== V && k !== VENDOR).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
      .then(() => { prefetchVendor(); })        // not awaited: the app opens at once
  );
});

self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== location.origin) return;
  if (u.pathname.includes('/vendor/')) {
    e.respondWith(
      caches.open(VENDOR).then(c => c.match(e.request, { ignoreSearch: true }).then(hit => hit || fetch(e.request).then(r => {
        if (r.ok) c.put(e.request, r.clone());
        return r;
      })))
    );
    return;
  }
  e.respondWith(
    fetch(e.request)
      .then(r => {
        if (r.ok) { const copy = r.clone(); caches.open(V).then(c => c.put(e.request, copy)); }
        return r;
      })
      .catch(() => caches.match(e.request).then(m => m || caches.match('index.html')))
  );
});
