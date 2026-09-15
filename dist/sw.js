const CACHE='economic-shell-2.1.2';
const ASSETS=['./','./index.html','./offline.js','./panel.js','./panel.css','./mobile.css','./vendor/supabase-2.116.0.js','./manifest.webmanifest','./icon.svg'];
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(ASSETS)))});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith('economic-shell-')&&key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',event=>{
  const url=new URL(event.request.url);
  // Never cache authentication responses, private receipts, or remote APIs here.
  if(event.request.method!=='GET'||url.origin!==location.origin)return;
  if(!ASSETS.some(path=>new URL(path,self.registration.scope).pathname===url.pathname))return;
  event.respondWith(caches.match(event.request).then(cached=>cached||fetch(event.request)));
});
