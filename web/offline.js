/* Device-local cache. Supabase RLS remains authoritative on every replay. */
(function (root) {
  'use strict';
  const dbName = 'economic-offline-v1';
  const nativeFetch = root.fetch.bind(root);
  let dbPromise, scope = '', owner = '', disconnected = !navigator.onLine, syncing = false;
  const listeners = new Set();
  function emit() { listeners.forEach(fn => fn()); }
  function db() {
    if (!dbPromise) dbPromise = new Promise((resolve, reject) => {
      const req = indexedDB.open(dbName, 1);
      req.onupgradeneeded = () => {
        req.result.createObjectStore('cache');
        req.result.createObjectStore('queue', { keyPath: 'id' });
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
    return dbPromise;
  }
  async function access(store, mode, action) {
    const database = await db();
    return new Promise((resolve, reject) => {
      const tx = database.transaction(store, mode);
      const req = action(tx.objectStore(store));
      tx.oncomplete = () => resolve(req.result);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error || new Error('No se pudo guardar en este dispositivo.'));
    });
  }
  const read = key => access('cache', 'readonly', s => s.get(key));
  const write = (key, value) => access('cache', 'readwrite', s => s.put(value, key));
  const all = () => access('queue', 'readonly', s => s.getAll());
  const put = item => access('queue', 'readwrite', s => s.put(item));
  const remove = id => access('queue', 'readwrite', s => s.delete(id));
  const pending = async () => (await all()).filter(x => x.scope === scope).sort((a,b) => a.createdAt.localeCompare(b.createdAt));
  const fail = message => new Response(JSON.stringify({ message, code: 'OFFLINE' }), { status: 503, headers: { 'Content-Type': 'application/json' } });
  const json = value => new Response(JSON.stringify(value), { status: 200, headers: { 'Content-Type': 'application/json' } });
  async function scopedFetch(input, options = {}) {
    const request = new Request(input, options), url = new URL(request.url);
    if (!url.pathname.startsWith('/rest/v1/') || !scope) return nativeFetch(request);
    const ownScope = scope;
    const key = ownScope + ':' + request.url;
    const isRead = request.method === 'GET';
    if (isRead) {
      try {
        if (!navigator.onLine) throw new TypeError('offline');
        const response = await nativeFetch(request);
        if (response.status >= 500) throw new TypeError('server unavailable');
        if (response.ok) {
          disconnected = false;
          const text = await response.clone().text();
          try { await write(key, { text, at: new Date().toISOString(), headers: [...response.headers] }); } catch (_) { /* reads remain available when storage is full */ }
          emit();
        }
        return response;
      } catch (error) {
        if (request.signal.aborted) throw error;
        disconnected = true; emit();
        const cached = await read(key);
        if (ownScope !== scope) return fail('La cuenta activa cambió.');
        if (cached) return new Response(cached.text, { status: 200, headers: cached.headers });
        return fail('Sin conexión. Esta información todavía no está guardada en este dispositivo.');
      }
    }
    // Mutations never silently succeed offline. Only the explicit new-movement flow queues.
    if (disconnected || !navigator.onLine) return fail('Esta acción necesita conexión. Puedes guardar un nuevo movimiento pendiente.');
    if (url.pathname.includes('/rpc/') && (await pending()).length) return fail('Sincroniza los movimientos pendientes antes de realizar esta operación.');
    return nativeFetch(request);
  }
  async function enqueue(payload) {
    if (!scope || payload.created_by !== owner || payload.updated_by !== owner) throw new Error('Inicia sesión antes de guardar.');
    const id = crypto.randomUUID();
    const item = { id, scope, owner, payload: { ...payload, id }, createdAt: new Date().toISOString(), error: null };
    await put(item); emit(); return item;
  }
  function matches(saved, payload) {
    return Object.entries(payload).every(([key, value]) => {
      if (typeof value === 'number') return Math.abs(Number(saved[key]) - value) <= 0.000001;
      if (key === 'client_id' && value === null && payload.project_id) return true; // server fills project's client
      return JSON.stringify(saved[key] ?? null) === JSON.stringify(value ?? null);
    });
  }
  async function flush(client) {
    if (syncing || !navigator.onLine || !scope) return { sent: 0 };
    syncing = true; emit();
    let sent = 0;
    const expected = scope;
    try {
      const { data, error } = await client.auth.getSession();
      if (error || data?.session?.user?.id !== owner) throw new Error('Vuelve a iniciar sesión para sincronizar.');
      const token = data.session.access_token;
      const config = JSON.parse(localStorage.getItem('finance_supabase_cfg_v1'));
      const endpoint = config.url.replace(/\/$/, '') + '/rest/v1/transactions';
      for (const item of await pending()) {
        if (scope !== expected) break;
        try {
          const headers = { apikey: config.key, Authorization: 'Bearer ' + token, 'Content-Type': 'application/json', Prefer: 'return=representation' };
          // Primary-key UUID makes an uncertain response safe to retry.
          let res = await nativeFetch(endpoint, { method: 'POST', headers, body: JSON.stringify(item.payload) });
          let body = await res.json();
          if (res.status === 409 && body.code === '23505') {
            res = await nativeFetch(endpoint + '?id=eq.' + item.id + '&select=*', { headers });
            const rows = await res.json();
            if (!res.ok || !Array.isArray(rows) || !rows[0] || !matches(rows[0], item.payload)) throw new Error('Conflicto: revisa este movimiento antes de volver a enviarlo.');
          } else if (!res.ok) throw new Error(body.message || 'No se pudo sincronizar el movimiento.');
          await remove(item.id); sent++; disconnected = false;
        } catch (err) {
          item.error = err.message; await put(item);
          if (err instanceof TypeError) { disconnected = true; break; }
        }
      }
      return { sent };
    } finally { syncing = false; emit(); }
  }
  async function clear() {
    await access('cache', 'readwrite', s => s.clear());
    await access('queue', 'readwrite', s => s.clear());
    localStorage.removeItem('economic-offline-user'); scope = ''; owner = ''; emit();
  }
  root.EconOffline = {
    fetch: scopedFetch, enqueue, pending, flush, clear, matches,
    isOffline: () => disconnected || !navigator.onLine,
    isSyncing: () => syncing,
    setIdentity(config, user) { owner = user?.id || ''; scope = owner ? config.url + ':' + owner : ''; },
    async discard(id) { const item = (await pending()).find(x => x.id === id); if (item) await remove(id); emit(); },
    subscribe(fn) { listeners.add(fn); },
    get scope() { return scope; }
  };
  addEventListener('offline', () => { disconnected = true; emit(); });
  addEventListener('online', () => { disconnected = false; emit(); });
})(window);
