const {test}=require('node:test');const assert=require('node:assert/strict');
const {JSDOM,VirtualConsole}=require('jsdom');const {IDBFactory}=require('fake-indexeddb');
const fs=require('node:fs'),path=require('node:path');
test('the self-contained app initializes all panel sections without runtime errors',async()=>{
  const errors=[];const vc=new VirtualConsole();vc.on('jsdomError',e=>errors.push(e));
  const dom=new JSDOM(fs.readFileSync(path.join(__dirname,'../android/app/src/main/assets/index.html'),'utf8'),{
    url:'https://app.lineagrafica.local/',runScripts:'dangerously',virtualConsole:vc,
    beforeParse(w){w.fetch=async()=>new Response('[]',{headers:{'Content-Type':'application/json'}});w.Request=Request;w.Response=Response;w.Headers=Headers;w.structuredClone=structuredClone;w.indexedDB=new IDBFactory();w.scrollTo=()=>{};w.matchMedia=()=>({matches:false,addListener(){},removeListener(){}});w.crypto.randomUUID=()=>require('node:crypto').randomUUID();}
  });
  await new Promise(r=>setTimeout(r,400));
  assert.deepEqual(errors.map(e=>e.message),[]);
  const d=dom.window.document;
  assert.equal(d.querySelectorAll('.panel-nav button').length,8);
  for(const id of ['v12Dashboard','transactionForm','v20CRM','v15Accounts','v16Planning','v14Reports','activityList','securityToggle'])assert.ok(d.getElementById(id),id+' is retained');
  assert.equal(d.querySelectorAll('.panel-page:not([hidden])').length,1);
  d.querySelectorAll('.panel-nav button')[1].click();
  assert.equal(d.querySelector('.panel-page:not([hidden]) h2').textContent,'Movimientos');
  assert.equal(d.getElementById('authScreen').classList.contains('hidden'),false);
  dom.window.close();
});

test('saved session and cached business reopen offline and a new movement stays pending',async()=>{
  const errors=[];const vc=new VirtualConsole();vc.on('jsdomError',e=>errors.push(e));
  const factory=new IDBFactory();let online=true;
  const uid='11111111-1111-4111-8111-111111111111',bid='22222222-2222-4222-8222-222222222222';
  const auth={access_token:'eyJhbGciOiJIUzI1NiJ9.'+Buffer.from(JSON.stringify({sub:uid,exp:4102444800})).toString('base64url')+'.signature',refresh_token:'refresh-token',expires_at:4102444800,expires_in:3600,token_type:'bearer',user:{id:uid,email:'test@example.test',aud:'authenticated'}};
  const html=fs.readFileSync(path.join(__dirname,'../android/app/src/main/assets/index.html'),'utf8');
  const run=storage=>new JSDOM(html,{
    url:'https://app.lineagrafica.local/',runScripts:'dangerously',virtualConsole:vc,
    beforeParse(w){
      Object.defineProperty(w.navigator,'onLine',{get:()=>online});
      w.Request=Request;w.Response=Response;w.Headers=Headers;w.structuredClone=structuredClone;w.indexedDB=factory;w.scrollTo=()=>{};w.confirm=()=>true;w.matchMedia=()=>({matches:false,addListener(){},removeListener(){}});w.crypto.randomUUID=()=>require('node:crypto').randomUUID();
      w.fetch=async(input,opts)=>{
        if(!online)throw new TypeError('offline');
        const req=new Request(input,opts),url=new URL(req.url);
        let data=[];
        if(url.pathname.endsWith('/business_members'))data=[{business_id:bid,role:'owner'}];
        if(url.pathname.endsWith('/businesses'))data={id:bid,name:'Test business',join_code:'TEST1234'};
        if(url.pathname.endsWith('/categories'))data=[{id:'cat',name:'Servicios'}];
        if(url.pathname.endsWith('/rates'))data={bcv:{rate:100},airtm:{rate:110},fetchedAt:new Date().toISOString()};
        return new Response(JSON.stringify(data),{headers:{'Content-Type':'application/json'}});
      };
      for(const[k,v]of Object.entries(storage||{'sb-chfrcfaldbdhmtgtoxcm-auth-token':JSON.stringify(auth)}))w.localStorage.setItem(k,v);
    }
  });
  const first=run();
  await new Promise(r=>setTimeout(r,600));
  // Realtime is a separate transport. This test covers REST cache and session recovery.
  first.window.eval('cleanupRealtime()');
  assert.equal(first.window.document.getElementById('businessName').textContent,'Test business');
  const storage={};for(let i=0;i<first.window.localStorage.length;i++){const k=first.window.localStorage.key(i);storage[k]=first.window.localStorage.getItem(k)}
  first.window.close();online=false;
  const expired=JSON.parse(storage['sb-chfrcfaldbdhmtgtoxcm-auth-token']);expired.expires_at=1;storage['sb-chfrcfaldbdhmtgtoxcm-auth-token']=JSON.stringify(expired);
  const second=run(storage);await new Promise(r=>setTimeout(r,500));
  const w=second.window,d=w.document;
  assert.equal(d.getElementById('appScreen').classList.contains('hidden'),false);
  assert.equal(d.getElementById('businessName').textContent,'Test business');
  d.getElementById('amount').value='25';d.getElementById('originalCurrency').value='USD';d.getElementById('description').value='Offline service';
  await d.getElementById('transactionForm').onsubmit({preventDefault(){}});
  const items=await w.EconOffline.pending();assert.equal(items.length,1);assert.equal(items[0].payload.amount_original,25);assert.equal(items[0].payload.created_by,uid);
  assert.equal(w.eval('transactions.length'),0);
  assert.deepEqual(errors.filter(e=>e.type==='unhandled exception').map(e=>e.message),[]);
  w.eval('cleanupRealtime()');w.close();
});
