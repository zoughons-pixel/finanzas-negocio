const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const {IDBFactory}=require('fake-indexeddb');
const crypto=require('node:crypto').webcrypto;
const code=fs.readFileSync(require('node:path').join(__dirname,'../web/offline.js'),'utf8');
const cfg={url:'https://test.supabase.co',key:'public-test-key'};
function setup(fetcher){
  const handlers={};const nav={onLine:true};
  const localStorage={getItem:()=>JSON.stringify(cfg),removeItem(){}};
  const context={navigator:nav,fetch:fetcher,indexedDB:new IDBFactory(),Request,Response,Headers,URL,crypto,localStorage,addEventListener:(name,fn)=>handlers[name]=fn};
  context.window=context;vm.runInNewContext(code,context);const offline=context.EconOffline;
  offline.setIdentity(cfg,{id:'owner'});
  return {offline,nav,handlers};
}
const session={auth:{getSession:async()=>({data:{session:{user:{id:'owner'},access_token:'token'}}})}};
const payload={business_id:'business',created_by:'owner',updated_by:'owner',type:'income',amount_original:10,usd_bcv:10,client_id:null,project_id:null};
test('cached financial reads are isolated by user and never replace a 403',async()=>{
  let status=200;
  const {offline,nav}=setup(async()=>new Response(JSON.stringify([{id:'private-row'}]),{status}));
  const url=cfg.url+'/rest/v1/transactions?business_id=eq.business';
  assert.equal((await offline.fetch(url)).status,200);
  nav.onLine=false;
  assert.equal((await (await offline.fetch(url)).json())[0].id,'private-row');
  offline.setIdentity(cfg,{id:'partner'});
  assert.equal((await offline.fetch(url)).status,503);
  offline.setIdentity(cfg,{id:'owner'});nav.onLine=true;status=403;
  assert.equal((await offline.fetch(url)).status,403);
});
test('retry after server acceptance and lost response creates exactly one movement',async()=>{
  let stored=null,posts=0;
  const {offline}=setup(async(input,opts)=>{
    if(opts?.method==='POST'){
      posts++;
      if(!stored){stored=JSON.parse(opts.body);throw new TypeError('connection lost after commit')}
      return new Response(JSON.stringify({code:'23505'}),{status:409});
    }
    return new Response(JSON.stringify([stored]));
  });
  const item=await offline.enqueue(payload);
  await offline.flush(session);assert.equal((await offline.pending()).length,1);
  assert.equal((await offline.flush(session)).sent,1);
  assert.equal((await offline.pending()).length,0);assert.equal(stored.id,item.id);assert.equal(posts,2);
});
test('closed month rejection and role denial retain pending data visibly',async()=>{
  const {offline}=setup(async()=>new Response(JSON.stringify({message:'El mes está cerrado'}),{status:403}));
  await offline.enqueue(payload);await offline.flush(session);
  const items=await offline.pending();assert.equal(items.length,1);assert.equal(items[0].error,'El mes está cerrado');
});
test('conflicting UUID is not silently accepted and concurrent sync is serialized',async()=>{
  let posts=0;
  const {offline}=setup(async(input,opts)=>{
    if(opts?.method==='POST'){posts++;await new Promise(r=>setTimeout(r,10));return new Response(JSON.stringify({code:'23505'}),{status:409})}
    return new Response(JSON.stringify([{...payload,amount_original:999}]));
  });
  await offline.enqueue(payload);
  await Promise.all([offline.flush(session),offline.flush(session)]);
  assert.equal(posts,1);assert.match((await offline.pending())[0].error,/Conflicto/);
});
test('no session for the queue owner means no replay; clearing removes private cache',async()=>{
  let calls=0;
  const {offline}=setup(async()=>{calls++;return new Response('[]')});
  await offline.enqueue(payload);
  await assert.rejects(offline.flush({auth:{getSession:async()=>({data:{session:{user:{id:'partner'}}}})}}),/iniciar sesión/);
  assert.equal(calls,0);await offline.clear();offline.setIdentity(cfg,{id:'owner'});assert.equal((await offline.pending()).length,0);
});
