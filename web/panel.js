(function () {
  'use strict';
  const offline = window.EconOffline;
  const container = document.querySelector('#appScreen .container');
  const nav = document.createElement('nav'); nav.className = 'panel-nav'; nav.setAttribute('aria-label','Secciones de E-conomic');
  nav.innerHTML = '<div class="panel-brand"><b>E-conomic</b><span>Control del negocio</span></div>';
  const pageRoot = document.createElement('div'); pageRoot.className = 'panel-pages';
  const pages = new Map(); let active = 'Resumen';
  const navMeta = {
    'Resumen':['⌂','Inicio'],
    'Movimientos':['↕','Movimientos'],
    'Clientes y proyectos':['♙','Clientes'],
    'Cobros y pagos':['◷','Cuentas'],
    'Planificación':['◎','Planes'],
    'Reportes y cierres':['▤','Reportes'],
    'Actividad':['◉','Actividad'],
    'Ajustes':['⚙','Ajustes']
  };
  function page(name, elements) {
    const section = document.createElement('section'); section.className = 'panel-page';
    const heading=document.createElement('h2');heading.className='panel-heading';heading.textContent=name;section.append(heading);
    elements.filter(Boolean).forEach(el=>section.append(el));pageRoot.append(section);pages.set(name,section);
    const button=document.createElement('button'),meta=navMeta[name]||['•',name];button.type='button';button.dataset.page=name;button.setAttribute('aria-label',name);button.innerHTML=`<span class="panel-nav-icon" aria-hidden="true">${meta[0]}</span><span class="panel-nav-label">${meta[1]}</span>`;button.onclick=()=>select(name);nav.append(button);
  }
  function select(name) {
    active=name;
    pages.forEach((section,key)=>section.hidden=key!==name);
    nav.querySelectorAll('button').forEach(btn=>{const current=btn.dataset.page===name;btn.classList.toggle('active',current);btn.setAttribute('aria-current',current?'page':'false');if(current&&matchMedia('(max-width:760px)').matches)btn.scrollIntoView({inline:'center',block:'nearest'})});
    scrollTo({top:0,behavior:'smooth'});
  }
  const cardFor = id => $(id)?.closest('.card');
  page('Resumen',[document.querySelector('#appScreen .stats'),$('v12Dashboard'),cardFor('refreshRates')]);
  const movements=document.createElement('div');movements.className='panel-movements';movements.append(cardFor('transactionForm'),cardFor('transactions'));
  page('Movimientos',[movements]);
  page('Clientes y proyectos',[$('v20CRM')]);
  page('Cobros y pagos',[$('v15Accounts')]);
  page('Planificación',[$('v16Planning')]);
  page('Reportes y cierres',[$('v14Reports')]);
  page('Actividad',[cardFor('activityList')]);
  const security=document.createElement('section');security.className='card';
  security.innerHTML='<h3>Seguridad del dispositivo</h3><p id="securityDescription">La biometría está disponible en la aplicación Android. En este navegador, cierra sesión al terminar si compartes el equipo.</p><div class="actions"><button type="button" id="securityToggle" class="btn btn-primary hidden">Activar biometría</button><button type="button" id="securityLock" class="btn btn-secondary hidden">Bloquear ahora</button></div>';
  page('Ajustes',[security,cardFor('categoryChips'),cardFor('joinCodeView')]);
  document.querySelector('#appScreen .grid')?.remove();
  container.append(pageRoot);$('appScreen').prepend(nav);
  const footer=document.querySelector('.footer');if(footer){footer.textContent='E-conomic 2.1.2 · Finanzas del negocio';container.append(footer)}
  const banner=document.createElement('section');banner.className='offline-banner';banner.setAttribute('aria-live','polite');
  banner.innerHTML='<div><strong id="offlineState">Conectando…</strong><p id="offlineDetail"></p></div><div class="actions"><button type="button" class="btn btn-secondary" id="offlineSync">Sincronizar</button><button type="button" class="btn btn-primary" id="quickMovement">+ Movimiento</button></div>';
  container.prepend(banner);
  const queue=document.createElement('section');queue.className='card queue-card';queue.hidden=true;
  queue.innerHTML='<h3>Pendientes en este dispositivo</h3><p>Estos movimientos aún no forman parte de los saldos ni reportes confirmados. Se validarán con los permisos y cierres actuales al sincronizar.</p><div id="offlineQueue"></div>';
  banner.after(queue);
  $('quickMovement').onclick=()=>{select('Movimientos');$('amount').focus()};
  let refreshing=false;
  async function sync() {
    if(refreshing||!user||!navigator.onLine)return;
    refreshing=true;$('offlineSync').disabled=true;
    try {
      const result=await offline.flush(sb);
      await routeAfterAuth();
      if(result.sent)toast(result.sent+' movimiento(s) sincronizado(s)');
    }catch(err){toast(err.message)}finally{refreshing=false;$('offlineSync').disabled=false;renderOffline()}
  }
  $('offlineSync').onclick=sync;
  let renderTimer;
  offline.subscribe(()=>{clearTimeout(renderTimer);renderTimer=setTimeout(renderOffline,80)});
  async function renderOffline() {
    const items=await offline.pending().catch(()=>[]);
    const off=offline.isOffline();
    $('offlineState').textContent=offline.isSyncing()?'Sincronizando pendientes…':off?'Sin conexión · copia local':items.length?'Conectado · movimientos pendientes':'Conectado';
    $('offlineDetail').textContent=off?'Puedes consultar lo guardado y registrar nuevos movimientos. Comprobantes, ediciones, cobros y cierres necesitan conexión.':items.length?'Revisa y sincroniza los pendientes para actualizar los saldos.':'Tus cuentas, movimientos y reportes se comparten con Android.';
    banner.classList.toggle('is-offline',off||items.length>0);
    $('offlineSync').disabled=off||refreshing||offline.isSyncing();
    queue.hidden=!items.length;
    $('offlineQueue').replaceChildren();
    for(const item of items){
      const row=document.createElement('article');row.className='queue-item';
      const text=document.createElement('div');const title=document.createElement('strong');title.textContent=(item.payload.type==='income'?'Ingreso':'Egreso')+' · '+item.payload.amount_original+' '+item.payload.original_currency;
      const desc=document.createElement('p');desc.textContent=(item.payload.description||item.payload.category)+' · '+formatDate(item.payload.occurred_on);
      const status=document.createElement('p');status.className='queue-status';status.textContent=item.error||'Pendiente de enviar';text.append(title,desc,status);
      const remove=document.createElement('button');remove.type='button';remove.className='btn btn-danger';remove.textContent='Descartar';remove.onclick=async()=>{if(confirm('¿Descartar este movimiento pendiente? No se borrará ningún movimiento que ya esté confirmado en el servidor.'))await offline.discard(item.id)};
      row.append(text,remove);$('offlineQueue').append(row);
    }
    if(off)setSync('error','Sin conexión');
  }
  const oldRoute=routeAfterAuth;let autoSyncedScope='';
  routeAfterAuth=async function(){
    await oldRoute();await renderOffline();
    if(business&&navigator.onLine&&offline.scope!==autoSyncedScope){autoSyncedScope=offline.scope;if((await offline.pending()).length)setTimeout(sync,0)}
  };
  async function secureLogout(){
    const items=await offline.pending();
    if(items.length){toast('Sincroniza o descarta tus movimientos pendientes antes de cerrar sesión.');return}
    cleanupRealtime();await sb.auth.signOut({scope:'local'});await offline.clear();
    business=null;membership=null;user=null;session=null;transactions=[];categories=[];activityLogs=[];
    // Reload destroys all extension state, clients, projects and cached reports.
    location.reload();
  }
  logout=secureLogout;$('logoutBtn').onclick=secureLogout;$('logoutFromBusiness').onclick=secureLogout;
  $('changeConfig').onclick=async()=>{if((await offline.pending()).length){toast('Sincroniza tus pendientes antes de cambiar de proyecto.');return}if(confirm('¿Cambiar el proyecto y borrar la copia local de este dispositivo?')){await sb.auth.signOut({scope:'local'});await offline.clear();localStorage.removeItem(STORE.cfg);location.reload()}};
  function securityState(){
    if(!window.EconSecurity)return;
    const enabled=EconSecurity.isEnabled();
    $('securityDescription').textContent=enabled?'Protección activada. Al volver a abrir la app se solicita tu biometría o el PIN de Android.':'Activa el bloqueo para proteger la información guardada en este teléfono.';
    $('securityToggle').classList.remove('hidden');$('securityToggle').textContent=enabled?'Desactivar protección':'Activar biometría / PIN';
    $('securityLock').classList.toggle('hidden',!enabled);
  }
  $('securityToggle').onclick=()=>EconSecurity.setEnabled(!EconSecurity.isEnabled());$('securityLock').onclick=()=>EconSecurity.lock();
  addEventListener('economic-security-change',securityState);
  addEventListener('online',()=>{sb?.auth.startAutoRefresh();sync()});
  addEventListener('offline',()=>{sb?.auth.stopAutoRefresh();renderOffline()});
  addEventListener('DOMContentLoaded',()=>{securityState();renderOffline()});
  const oldEdit=window.editTx;window.editTx=id=>{select('Movimientos');oldEdit(id)};
  // Labels for inherited form controls, keyboard and browser autofill.
  document.querySelectorAll('input,select,textarea').forEach(el=>{const label=el.closest('.form-group')?.querySelector('label');if(label&&el.id)label.htmlFor=el.id;else if(!el.hasAttribute('aria-label'))el.setAttribute('aria-label',el.placeholder||el.options?.[0]?.textContent||el.id)});
  $('authEmail').autocomplete='username';$('authPassword').autocomplete='current-password';
  select('Resumen');securityState();
  if('serviceWorker' in navigator && location.hostname!=='app.lineagrafica.local') navigator.serviceWorker.register('./sw.js').catch(()=>{});
})();
