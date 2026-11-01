/* 윗블 서비스 워커: 한 번 열면 인터넷 없이도 앱과 성경 본문을 볼 수 있게 저장해 둔다.
 * - 화면(index.html 등): 인터넷이 되면 최신 버전, 안 되면 저장본 (network-first)
 * - 성경 본문(data/krv.json): 저장본을 먼저 사용 (cache-first)
 *   → 성경 데이터나 아이콘을 바꿨으면 아래 VERSION 숫자를 올려야 새 파일로 교체된다.
 * - 구글 폰트: 처음 받을 때 저장해 두고 재사용
 */
const VERSION = 'v2';
const CACHE = 'withble-' + VERSION;
const FONT_CACHE = 'withble-fonts';
const PRECACHE = [
  './',
  'index.html',
  'manifest.webmanifest',
  'vendor/supabase-js-2.117.3.js',
  'data/krv.json',
  'icons/icon-192.png',
  'icons/icon-512.png',
  'icons/icon-maskable-512.png',
  'icons/apple-touch-icon.png',
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(PRECACHE)).then(() => self.skipWaiting()));
});

// 이전 버전의 저장본 정리
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE && k !== FONT_CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    e.respondWith(cacheFirst(req, FONT_CACHE));
    return;
  }
  if (url.origin !== self.location.origin) return;

  if (url.pathname.endsWith('/data/krv.json')) {
    e.respondWith(cacheFirst(req, CACHE));
  } else {
    e.respondWith(networkFirst(req));
  }
});

async function cacheFirst(req, name) {
  const hit = await caches.match(req);
  if (hit) return hit;
  const res = await fetch(req);
  if (res.ok || res.type === 'opaque') (await caches.open(name)).put(req, res.clone());
  return res;
}

async function networkFirst(req) {
  try {
    const res = await fetch(req);
    if (res.ok) (await caches.open(CACHE)).put(req, res.clone());
    return res;
  } catch (err) {
    const hit = await caches.match(req, { ignoreSearch: true });
    if (hit) return hit;
    if (req.mode === 'navigate') return caches.match('index.html');
    throw err;
  }
}
