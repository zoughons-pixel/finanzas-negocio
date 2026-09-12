-- E-conomic v1.4 frontend OTA — reportes PDF/Excel y cierres mensuales.
do $migration$
declare
  v_html text;
  v_new text;
  v_addon text;
  v_sha text;
  v_id bigint;
begin
  if exists (select 1 from public.app_releases where version_code = 7 and version = '1.4.0') then
    return;
  end if;

  select html into v_html
  from public.app_releases
  where is_active
  order by version_code desc, id desc
  limit 1;

  if v_html is null then raise exception 'No active frontend release found'; end if;

  v_addon := $v14$
<script src="https://cdn.jsdelivr.net/npm/jspdf@2.5.2/dist/jspdf.umd.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/jspdf-autotable@3.8.4/dist/jspdf.plugin.autotable.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js"></script>
<style id="v14Style">
.v14-reports{overflow:hidden}.v14-toolbar{display:flex;align-items:end;justify-content:space-between;gap:12px;flex-wrap:wrap}.v14-toolbar-left{display:flex;gap:9px;align-items:end;flex-wrap:wrap}.v14-month-wrap{min-width:180px}.v14-month-wrap label{margin-bottom:5px}.v14-status{display:inline-flex;align-items:center;border:1px solid var(--border);background:var(--card2);border-radius:999px;padding:9px 12px;font-size:11px;font-weight:900;min-height:44px}.v14-status.closed{color:var(--green)}.v14-status.reopened{color:var(--orange)}.v14-summary{display:grid;grid-template-columns:repeat(5,1fr);gap:9px;margin:14px 0}.v14-metric{background:var(--card2);border:1px solid var(--border);border-radius:12px;padding:12px}.v14-metric span{display:block;font-size:9px;color:var(--muted);font-weight:900;text-transform:uppercase}.v14-metric strong{display:block;margin-top:5px;font-size:16px}.v14-metric small{display:block;margin-top:3px;color:var(--muted);font-size:9px}.v14-warning{border:1px solid color-mix(in srgb,var(--orange) 35%,var(--border));background:color-mix(in srgb,var(--orange) 9%,var(--card));border-radius:11px;padding:10px 12px;font-size:10px;line-height:1.5;margin-bottom:12px}.v14-warning.ok{border-color:color-mix(in srgb,var(--green) 30%,var(--border));background:color-mix(in srgb,var(--green) 8%,var(--card))}.v14-history-title{font-size:11px;font-weight:900;margin:12px 0 7px}.v14-history{display:grid;gap:6px}.v14-history-row{width:100%;display:grid;grid-template-columns:1fr auto auto;gap:10px;align-items:center;text-align:left;background:var(--card2);border:1px solid var(--border);border-radius:10px;padding:9px 11px;color:var(--text)}.v14-history-row strong{font-size:11px}.v14-history-row span{font-size:9px;color:var(--muted)}.v14-lock{display:inline-flex;margin-top:5px;padding:3px 7px;border-radius:10px;background:color-mix(in srgb,var(--green) 10%,var(--card));color:var(--green);font-size:9px;font-weight:900}.v14-owner-note{font-size:9px;color:var(--muted);margin-top:7px}
@media(max-width:900px){.v14-summary{grid-template-columns:1fr 1fr 1fr}.v14-toolbar{align-items:stretch}.v14-toolbar-left{width:100%}.v14-month-wrap{flex:1}}
@media(max-width:600px){.v14-summary{grid-template-columns:1fr 1fr}.v14-toolbar-left{display:grid;grid-template-columns:1fr 1fr;width:100%}.v14-month-wrap{grid-column:1/-1}.v14-toolbar .actions{width:100%}.v14-toolbar .actions .btn{flex:1}.v14-history-row{grid-template-columns:1fr auto}.v14-history-row span:last-child{grid-column:1/-1}}
</style>
<script id="v14Script">
(function(){
  let v14Closures=[],v14Receipts=[],v14Members=[],v14ClosureChannel=null,v14Ready=false;
  const V14_PDF='application/pdf',V14_XLSX='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  const v14Pad=n=>String(n).padStart(2,'0');
  function v14MonthKey(d=new Date()){return d.getFullYear()+'-'+v14Pad(d.getMonth()+1)}
  function v14MonthLabel(key){const p=String(key||'').split('-').map(Number);if(!p[0]||!p[1])return key;return new Date(p[0],p[1]-1,1).toLocaleDateString('es-VE',{month:'long',year:'numeric'})}
  function v14PeriodStart(key){return /^\d{4}-\d{2}$/.test(key||'')?key+'-01':v14MonthKey()+'-01'}
  function v14Closure(key){return v14Closures.find(c=>String(c.period_start||'').slice(0,7)===key)||null}
  function v14IsClosedDate(date){const key=String(date||'').slice(0,7),c=v14Closure(key);return !!c&&c.status==='closed'}
  function v14Rows(key){return (transactions||[]).filter(t=>String(t.occurred_on||'').slice(0,7)===key)}
  function v14ReportRows(key){const c=v14Closure(key);return c?.status==='closed'&&Array.isArray(c?.snapshot?.transactions)?c.snapshot.transactions:v14Rows(key)}
  function v14Num(v){return Number(v)||0}
  function v14LiveSummary(key){
    const rows=v14Rows(key),start=v14PeriodStart(key),before=(transactions||[]).filter(t=>(t.occurred_on||'')<start);
    const r={count:rows.length,incomeUsd:0,expenseUsd:0,incomeVes:0,expenseVes:0,incomeUsdc:0,expenseUsdc:0,openingUsd:0,openingVes:0,openingUsdc:0};
    before.forEach(t=>{const s=t.type==='income'?1:-1;r.openingUsd+=s*v14Num(t.usd_bcv);r.openingVes+=s*v14Num(t.ves);r.openingUsdc+=s*v14Num(t.usdc_airtm)});
    rows.forEach(t=>{if(t.type==='income'){r.incomeUsd+=v14Num(t.usd_bcv);r.incomeVes+=v14Num(t.ves);r.incomeUsdc+=v14Num(t.usdc_airtm)}else{r.expenseUsd+=v14Num(t.usd_bcv);r.expenseVes+=v14Num(t.ves);r.expenseUsdc+=v14Num(t.usdc_airtm)}});
    r.netUsd=r.incomeUsd-r.expenseUsd;r.netVes=r.incomeVes-r.expenseVes;r.netUsdc=r.incomeUsdc-r.expenseUsdc;r.closingUsd=r.openingUsd+r.netUsd;r.closingVes=r.openingVes+r.netVes;r.closingUsdc=r.openingUsdc+r.netUsdc;return r;
  }
  function v14Summary(key){
    const c=v14Closure(key);if(c?.status==='closed')return {count:Number(c.transaction_count)||0,incomeUsd:v14Num(c.income_usd),expenseUsd:v14Num(c.expense_usd),netUsd:v14Num(c.net_usd),incomeVes:v14Num(c.income_ves),expenseVes:v14Num(c.expense_ves),netVes:v14Num(c.net_ves),incomeUsdc:v14Num(c.income_usdc),expenseUsdc:v14Num(c.expense_usdc),netUsdc:v14Num(c.net_usdc),openingUsd:v14Num(c.opening_usd),closingUsd:v14Num(c.closing_usd),openingVes:v14Num(c.opening_ves),closingVes:v14Num(c.closing_ves),openingUsdc:v14Num(c.opening_usdc),closingUsdc:v14Num(c.closing_usdc)};return v14LiveSummary(key)
  }
  function v14Warnings(key){
    const c=v14Closure(key);if(c?.status==='closed'&&c.warnings)return c.warnings;
    const receiptIds=new Set(v14Receipts.map(a=>a.transaction_id));let missing=0,other=0,noReceipt=0;
    v14Rows(key).forEach(t=>{if(!String(t.description||'').trim())missing++;if(!String(t.category||'').trim()||String(t.category||'').trim().toLowerCase()==='otros')other++;if(t.type==='expense'&&!receiptIds.has(t.id))noReceipt++});
    return {missing_description:missing,other_category:other,expense_without_receipt:noReceipt};
  }
  function v14Actor(id){const m=v14Members.find(x=>x.user_id===id);if(m?.role==='owner')return 'Propietario';if(m?.role==='partner')return 'Socio';return id===user?.id?'Tú':'Socio'}
  function v14Categories(rows){const map={};rows.forEach(t=>{const k=t.category||'Otros';if(!map[k])map[k]={category:k,income:0,expense:0,count:0};map[k].count++;if(t.type==='income')map[k].income+=v14Num(t.usd_bcv);else map[k].expense+=v14Num(t.usd_bcv)});return Object.values(map).sort((a,b)=>(b.income+b.expense)-(a.income+a.expense))}
  function v14ReceiptCount(id){return v14Receipts.filter(a=>a.transaction_id===id).length}

  function v14BuildUI(){
    if(v14Ready||$('v14Reports'))return;const grid=document.querySelector('#appScreen .grid');if(!grid)return;
    const card=document.createElement('section');card.id='v14Reports';card.className='card v14-reports';card.innerHTML=`
      <div class="section-head"><div><h2>Reportes y cierres mensuales</h2><div class="muted">PDF, Excel y cierre contable con bloqueo del período</div></div></div>
      <div class="v14-toolbar"><div class="v14-toolbar-left"><div class="v14-month-wrap"><label>Mes del reporte</label><input id="v14Month" type="month"></div><div id="v14Status" class="v14-status">En curso</div></div><div class="actions"><button id="v14Pdf" class="btn btn-secondary" type="button">PDF</button><button id="v14Excel" class="btn btn-secondary" type="button">Excel</button><button id="v14Close" class="btn btn-primary" type="button">Cerrar mes</button></div></div>
      <div class="v14-summary"><div class="v14-metric"><span>Saldo inicial</span><strong id="v14Opening">$0.00</strong><small id="v14OpeningSub"></small></div><div class="v14-metric"><span>Ingresos</span><strong id="v14Income" class="green">$0.00</strong><small id="v14IncomeSub"></small></div><div class="v14-metric"><span>Egresos</span><strong id="v14Expense" class="red">$0.00</strong><small id="v14ExpenseSub"></small></div><div class="v14-metric"><span>Resultado</span><strong id="v14Net">$0.00</strong><small id="v14Count"></small></div><div class="v14-metric"><span>Saldo final</span><strong id="v14Closing">$0.00</strong><small id="v14ClosingSub"></small></div></div>
      <div id="v14Warnings" class="v14-warning ok"></div><div class="v14-owner-note">Ambos socios pueden descargar reportes. Solo el propietario puede cerrar o reabrir un mes.</div>
      <div class="v14-history-title">Historial de cierres</div><div id="v14History" class="v14-history"></div>`;
    grid.parentNode.insertBefore(card,grid);const month=$('v14Month');month.value=$('v12Month')?.value||v14MonthKey();month.addEventListener('input',v14Render);$('v14Pdf').onclick=v14GeneratePdf;$('v14Excel').onclick=v14GenerateExcel;$('v14Close').onclick=v14ToggleClosure;v14Ready=true;
    $('v12Month')?.addEventListener('input',e=>{if($('v14Month')){$('v14Month').value=e.target.value;v14Render()}});
  }

  async function v14Load(){
    if(!sb||!business)return;const [c,a,m]=await Promise.all([
      sb.from('monthly_closures').select('*').eq('business_id',business.id).order('period_start',{ascending:false}).limit(36),
      sb.from('transaction_attachments').select('transaction_id').eq('business_id',business.id),
      sb.from('business_members').select('user_id,role').eq('business_id',business.id)
    ]);if(c.error){console.warn('closures',c.error);return}v14Closures=c.data||[];v14Receipts=a.error?[]:(a.data||[]);v14Members=m.error?[]:(m.data||[]);v14Render();try{renderTransactions()}catch(e){}
  }
  function v14Subscribe(){if(v14ClosureChannel&&sb){sb.removeChannel(v14ClosureChannel);v14ClosureChannel=null}if(!sb||!business)return;v14ClosureChannel=sb.channel('closures-'+business.id).on('postgres_changes',{event:'*',schema:'public',table:'monthly_closures',filter:`business_id=eq.${business.id}`},async()=>{await v14Load()}).subscribe()}

  function v14Render(){
    v14BuildUI();if(!$('v14Month'))return;const key=$('v14Month').value||v14MonthKey(),c=v14Closure(key),s=v14Summary(key),w=v14Warnings(key),status=c?.status==='closed'?'Cerrado':c?.status==='reopened'?'Reabierto':'En curso';
    $('v14Status').textContent=(c?.status==='closed'?'🔒 ':c?.status==='reopened'?'🔓 ':'')+status;$('v14Status').className='v14-status '+(c?.status||'open');
    $('v14Opening').textContent=moneyUSD(s.openingUsd);$('v14OpeningSub').textContent=moneyVES(s.openingVes)+' · '+moneyUSDC(s.openingUsdc);$('v14Income').textContent=moneyUSD(s.incomeUsd);$('v14IncomeSub').textContent=moneyVES(s.incomeVes)+' · '+moneyUSDC(s.incomeUsdc);$('v14Expense').textContent=moneyUSD(s.expenseUsd);$('v14ExpenseSub').textContent=moneyVES(s.expenseVes)+' · '+moneyUSDC(s.expenseUsdc);$('v14Net').textContent=moneyUSD(s.netUsd);$('v14Net').className=s.netUsd>=0?'green':'red';$('v14Count').textContent=`${s.count} movimiento${s.count===1?'':'s'}`;$('v14Closing').textContent=moneyUSD(s.closingUsd);$('v14Closing').className=s.closingUsd>=0?'green':'red';$('v14ClosingSub').textContent=moneyVES(s.closingVes)+' · '+moneyUSDC(s.closingUsdc);
    const totalWarn=v14Num(w.missing_description)+v14Num(w.other_category)+v14Num(w.expense_without_receipt);$('v14Warnings').className='v14-warning '+(totalWarn?'':'ok');$('v14Warnings').innerHTML=totalWarn?`Revisión antes del cierre: <strong>${v14Num(w.missing_description)}</strong> sin descripción · <strong>${v14Num(w.other_category)}</strong> en “Otros” · <strong>${v14Num(w.expense_without_receipt)}</strong> egresos sin comprobante.`:'Revisión del mes: no se detectaron advertencias básicas.';
    const btn=$('v14Close');if(membership?.role!=='owner'){btn.classList.add('hidden')}else{btn.classList.remove('hidden');btn.textContent=c?.status==='closed'?'Reabrir mes':'Cerrar mes';btn.className='btn '+(c?.status==='closed'?'btn-danger':'btn-primary')}
    $('v14History').innerHTML=v14Closures.length?v14Closures.slice(0,12).map(x=>`<button class="v14-history-row" type="button" data-v14-month="${String(x.period_start).slice(0,7)}"><strong>${esc(v14MonthLabel(String(x.period_start).slice(0,7)))}</strong><span>${x.status==='closed'?'🔒 Cerrado':'🔓 Reabierto'}</span><span>${moneyUSD(x.net_usd)} · ${x.transaction_count} mov.</span></button>`).join(''):'<div class="empty">Todavía no hay meses cerrados.</div>';
    document.querySelectorAll('[data-v14-month]').forEach(b=>b.onclick=()=>{$('v14Month').value=b.dataset.v14Month;v14Render();$('v14Reports').scrollIntoView({behavior:'smooth',block:'start'})});
  }

  async function v14ToggleClosure(){
    if(membership?.role!=='owner'){toast('Solo el propietario puede cerrar o reabrir meses');return}const key=$('v14Month').value||v14MonthKey(),c=v14Closure(key),btn=$('v14Close');
    if(c?.status==='closed'){
      const reason=prompt('Motivo de la reapertura de '+v14MonthLabel(key)+':');if(reason===null)return;if(!reason.trim()){toast('Debes indicar el motivo de la reapertura');return}if(!confirm('¿Reabrir '+v14MonthLabel(key)+'? Los movimientos volverán a poder modificarse y la acción quedará auditada.'))return;btn.disabled=true;try{const {error}=await sb.rpc('reopen_month',{p_business_id:business.id,p_period_start:v14PeriodStart(key),p_reason:reason.trim()});if(error)throw error;await Promise.all([v14Load(),loadActivity()]);toast('Mes reabierto')}catch(e){toast(e?.message||'No se pudo reabrir el mes')}finally{btn.disabled=false}return;
    }
    const w=v14Warnings(key),parts=[];if(v14Num(w.missing_description))parts.push(`${w.missing_description} sin descripción`);if(v14Num(w.other_category))parts.push(`${w.other_category} en “Otros”`);if(v14Num(w.expense_without_receipt))parts.push(`${w.expense_without_receipt} egresos sin comprobante`);const warning=parts.length?'\n\nAdvertencias: '+parts.join(', ')+'.':'';
    if(!confirm(`¿Cerrar ${v14MonthLabel(key)}?\n\nDespués del cierre no se podrán crear, editar ni eliminar movimientos o comprobantes de ese mes hasta que el propietario lo reabra.${warning}`))return;btn.disabled=true;try{const {error}=await sb.rpc('close_month',{p_business_id:business.id,p_period_start:v14PeriodStart(key)});if(error)throw error;await Promise.all([v14Load(),loadActivity()]);toast('Mes cerrado correctamente')}catch(e){toast(e?.message||'No se pudo cerrar el mes')}finally{btn.disabled=false}
  }

  function v14StatusText(key){const c=v14Closure(key);return c?.status==='closed'?'Cerrado':c?.status==='reopened'?'Reabierto':'En curso'}
  function v14FileStem(key){return 'E-conomic_'+key.replace('-','_')+'_'+String(business?.name||'Negocio').replace(/[^A-Za-z0-9_-]+/g,'_').slice(0,40)}
  function v14Base64Blob(base64,mime){const bin=atob(base64),chunks=[];for(let i=0;i<bin.length;i+=8192){const slice=bin.slice(i,i+8192),arr=new Uint8Array(slice.length);for(let j=0;j<slice.length;j++)arr[j]=slice.charCodeAt(j);chunks.push(arr)}return new Blob(chunks,{type:mime})}
  function v14Save(name,mime,base64){try{if(window.EconNative&&typeof window.EconNative.saveReport==='function'){window.EconNative.saveReport(name,mime,base64);return}const blob=v14Base64Blob(base64,mime),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),30000);toast('Reporte generado')}catch(e){toast('No se pudo guardar el reporte')}}
  function v14Fmt(v){return Number(v14Num(v).toFixed(2))}
  function v14Short(v,n=70){const s=String(v??'');return s.length>n?s.slice(0,n-1)+'…':s}

  function v14GeneratePdf(){
    const key=$('v14Month').value||v14MonthKey(),rows=v14ReportRows(key),s=v14Summary(key),cats=v14Categories(rows),w=v14Warnings(key),jsPDF=window.jspdf?.jsPDF;if(!jsPDF){toast('El generador PDF no está disponible. Revisa Internet.');return}const doc=new jsPDF({orientation:'landscape',unit:'pt',format:'a4'});if(typeof doc.autoTable!=='function'){toast('El módulo de tablas PDF no cargó');return}
    doc.setFontSize(18);doc.text('E-conomic - Reporte mensual',40,38);doc.setFontSize(11);doc.text(String(business?.name||'Negocio'),40,56);doc.setFontSize(9);doc.text(`Periodo: ${v14MonthLabel(key)}   Estado: ${v14StatusText(key)}   Generado: ${new Date().toLocaleString('es-VE')}`,40,73);
    doc.autoTable({startY:88,head:[['Indicador','USD · BCV','Bolívares','USDC · Airtm']],body:[['Saldo inicial',moneyUSD(s.openingUsd),moneyVES(s.openingVes),moneyUSDC(s.openingUsdc)],['Ingresos',moneyUSD(s.incomeUsd),moneyVES(s.incomeVes),moneyUSDC(s.incomeUsdc)],['Egresos',moneyUSD(s.expenseUsd),moneyVES(s.expenseVes),moneyUSDC(s.expenseUsdc)],['Resultado',moneyUSD(s.netUsd),moneyVES(s.netVes),moneyUSDC(s.netUsdc)],['Saldo final',moneyUSD(s.closingUsd),moneyVES(s.closingVes),moneyUSDC(s.closingUsdc)]],styles:{fontSize:8,cellPadding:4}});
    let y=doc.lastAutoTable.finalY+14;doc.setFontSize(10);doc.text(`Movimientos: ${s.count}   Advertencias: ${v14Num(w.missing_description)} sin descripción, ${v14Num(w.other_category)} en Otros, ${v14Num(w.expense_without_receipt)} egresos sin comprobante`,40,y);y+=10;
    if(cats.length){doc.autoTable({startY:y+6,head:[['Categoría','Ingresos USD','Egresos USD','Movimientos']],body:cats.map(c=>[c.category,moneyUSD(c.income),moneyUSD(c.expense),String(c.count)]),styles:{fontSize:7,cellPadding:3}});y=doc.lastAutoTable.finalY+15}
    doc.autoTable({startY:y,head:[['Fecha','Tipo','Categoría','Descripción','Referencia','Original','USD BCV','VES','USDC','Registrado por']],body:rows.map(t=>[formatDate(t.occurred_on),t.type==='income'?'Ingreso':'Egreso',t.category||'',v14Short(t.description,55),v14Short(t.reference,24),`${v14Fmt(t.amount_original)} ${t.original_currency}`,moneyUSD(t.usd_bcv),moneyVES(t.ves),moneyUSDC(t.usdc_airtm),v14Actor(t.created_by)]),styles:{fontSize:6.4,cellPadding:2.5,overflow:'linebreak'},columnStyles:{3:{cellWidth:130},4:{cellWidth:70}},didDrawPage:()=>{doc.setFontSize(7);doc.text('E-conomic · '+v14MonthLabel(key),40,doc.internal.pageSize.height-16)}});
    const base64=doc.output('datauristring').split(',')[1];v14Save(v14FileStem(key)+'_Reporte.pdf',V14_PDF,base64)
  }

  function v14GenerateExcel(){
    const key=$('v14Month').value||v14MonthKey(),rows=v14ReportRows(key),s=v14Summary(key),c=v14Closure(key),w=v14Warnings(key),X=window.XLSX;if(!X){toast('El generador Excel no está disponible. Revisa Internet.');return}
    const wb=X.utils.book_new();const resumen=[['E-conomic - Reporte mensual'],['Negocio',business?.name||''],['Periodo',v14MonthLabel(key)],['Estado',v14StatusText(key)],['Generado',new Date().toLocaleString('es-VE')],[],['Indicador','USD · BCV','VES','USDC · Airtm'],['Saldo inicial',v14Fmt(s.openingUsd),v14Fmt(s.openingVes),v14Fmt(s.openingUsdc)],['Ingresos',v14Fmt(s.incomeUsd),v14Fmt(s.incomeVes),v14Fmt(s.incomeUsdc)],['Egresos',v14Fmt(s.expenseUsd),v14Fmt(s.expenseVes),v14Fmt(s.expenseUsdc)],['Resultado',v14Fmt(s.netUsd),v14Fmt(s.netVes),v14Fmt(s.netUsdc)],['Saldo final',v14Fmt(s.closingUsd),v14Fmt(s.closingVes),v14Fmt(s.closingUsdc)],[],['Movimientos',s.count],['Sin descripción',v14Num(w.missing_description)],['Categoría Otros',v14Num(w.other_category)],['Egresos sin comprobante',v14Num(w.expense_without_receipt)]];const wsR=X.utils.aoa_to_sheet(resumen);wsR['!cols']=[{wch:24},{wch:22},{wch:22},{wch:22}];X.utils.book_append_sheet(wb,wsR,'Resumen');
    const mov=rows.map(t=>({Fecha:t.occurred_on,Tipo:t.type==='income'?'Ingreso':'Egreso',Categoría:t.category||'',Descripción:t.description||'',Referencia:t.reference||'',Etiquetas:(t.tags||[]).join(', '),Notas:t.notes||'',Moneda:t.original_currency,Monto_original:v14Fmt(t.amount_original),Tasa_BCV:v14Fmt(t.bcv_rate),Tasa_Airtm:v14Fmt(t.airtm_rate),USD_BCV:v14Fmt(t.usd_bcv),VES:v14Fmt(t.ves),USDC_Airtm:v14Fmt(t.usdc_airtm),Comprobantes:v14ReceiptCount(t.id),Registrado_por:v14Actor(t.created_by)}));const wsM=X.utils.json_to_sheet(mov);wsM['!cols']=[{wch:12},{wch:10},{wch:18},{wch:34},{wch:18},{wch:24},{wch:38},{wch:10},{wch:14},{wch:13},{wch:13},{wch:13},{wch:16},{wch:14},{wch:14},{wch:16}];X.utils.book_append_sheet(wb,wsM,'Movimientos');
    const cats=v14Categories(rows).map(x=>({Categoría:x.category,Ingresos_USD:v14Fmt(x.income),Egresos_USD:v14Fmt(x.expense),Movimientos:x.count}));X.utils.book_append_sheet(wb,X.utils.json_to_sheet(cats),'Categorías');
    const cierre=[['Estado',v14StatusText(key)],['Cerrado el',c?.closed_at?new Date(c.closed_at).toLocaleString('es-VE'):''],['Cerrado por',c?.closed_by?v14Actor(c.closed_by):''],['Reaperturas',Number(c?.reopen_count)||0],['Última reapertura',c?.reopened_at?new Date(c.reopened_at).toLocaleString('es-VE'):''],['Motivo',c?.reopen_reason||'']];X.utils.book_append_sheet(wb,X.utils.aoa_to_sheet(cierre),'Cierre');const base64=X.write(wb,{bookType:'xlsx',type:'base64',compression:true});v14Save(v14FileStem(key)+'_Movimientos.xlsx',V14_XLSX,base64)
  }

  v14BuildUI();
  const v14OldCanManage=canManageTx;canManageTx=function(t){return !v14IsClosedDate(t?.occurred_on)&&v14OldCanManage(t)};
  const v14OldRenderTx=renderTransactions;renderTransactions=function(){v14OldRenderTx();const data=filtered(),cards=Array.from($('transactions')?.querySelectorAll('article.tx')||[]);cards.forEach((card,i)=>{card.querySelectorAll('.v14-lock').forEach(x=>x.remove());const t=data[i];if(t&&v14IsClosedDate(t.occurred_on)){const lock=document.createElement('div');lock.className='v14-lock';lock.textContent='🔒 Mes cerrado';card.querySelector('.tx-desc')?.insertAdjacentElement('afterend',lock)}})};
  const v14OldRenderAll=renderAllData;renderAllData=function(){v14OldRenderAll();v14Render()};
  const v14OldSubmit=$('transactionForm').onsubmit;$('transactionForm').onsubmit=async function(e){const date=$('date').value;if(v14IsClosedDate(date)){e.preventDefault();toast('Ese mes está cerrado. El propietario debe reabrirlo antes de guardar cambios.');return}return v14OldSubmit.call(this,e)};
  const v14OldCleanup=cleanupRealtime;cleanupRealtime=function(){if(v14ClosureChannel&&sb){sb.removeChannel(v14ClosureChannel);v14ClosureChannel=null}return v14OldCleanup()};
  const v14OldRoute=routeAfterAuth;routeAfterAuth=async function(){await v14OldRoute();if(business){v14BuildUI();await v14Load();v14Subscribe()}};
  const v14OldActivityTitle=activityTitle;activityTitle=function(a){if(a.action==='MONTH_CLOSED'){const p=a?.metadata?.period_start;return `${activityActor(a)} cerró ${p?v14MonthLabel(String(p).slice(0,7)):'un mes'}`}if(a.action==='MONTH_REOPENED'){const p=a?.metadata?.period_start;return `${activityActor(a)} reabrió ${p?v14MonthLabel(String(p).slice(0,7)):'un mes'}`}return v14OldActivityTitle(a)};
  renderActivity=function(){if(!$('activityList'))return;$('activityCount').textContent=`${activityLogs.length} evento${activityLogs.length===1?'':'s'}`;if(!activityLogs.length){$('activityList').innerHTML='<div class="empty">Todavía no hay actividad registrada.</div>';return}$('activityList').innerHTML=activityLogs.map(a=>{const icon=a.action==='CREATE_TRANSACTION'?'＋':a.action==='UPDATE_TRANSACTION'?'✎':a.action==='ATTACHMENT_ADDED'?'📎':a.action==='ATTACHMENT_REMOVED'?'−':a.action==='MONTH_CLOSED'?'🔒':a.action==='MONTH_REOPENED'?'🔓':'🗑',changes=activityChanges(a),s=activitySource(a);return `<div class="activity-item"><div class="activity-icon">${icon}</div><div><div class="activity-title">${activityTitle(a)}</div><div class="activity-meta">${new Date(a.created_at).toLocaleString('es-VE')}${s.category?' · '+esc(s.category):''}</div>${changes?`<div class="activity-change">${changes}</div>`:''}</div></div>`}).join('')};
  if(business){v14Load();v14Subscribe()}v14Render();try{renderTransactions();renderActivity()}catch(e){console.warn('v1.4 init',e)}
})();
</script>
$v14$;

  v_new := replace(v_html, '</body>', v_addon || E'\n</body>');
  if v_new = v_html then raise exception 'Could not inject v1.4 frontend'; end if;
  v_sha := encode(digest(convert_to(v_new,'UTF8'),'sha256'),'hex');
  select coalesce(max(id),0)+1 into v_id from public.app_releases;
  insert into public.app_releases(id,version_code,version,html,sha256,release_notes,is_active)
  values(v_id,7,'1.4.0',v_new,v_sha,'Reportes PDF/Excel, cierres mensuales, bloqueo y reapertura auditada.',true);
end;
$migration$;
