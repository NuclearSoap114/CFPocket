import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import {submissionMessage} from '../app/src/main/assets/web/cf-feedback.mjs';
const swift=readFileSync(new URL('../../TrainingLedger/TrainingCore/Sources/PocketCore/CFWebForm.swift',import.meta.url),'utf8');
const raw=name=>swift.match(new RegExp('public static let '+name+' = #"""\\n([\\s\\S]*?)\\n  """#'))[1];
const asset=name=>readFileSync(new URL('../app/src/main/assets/web/cf-'+name+'.js',import.meta.url),'utf8').trimEnd();
const snapshot=asset('snapshot'), dispatch=asset('dispatch');
function fixture({url='https://codeforces.com/contest/4/submit/A',action='',field='submittedProblemIndex',value='A',extra='',button='<input type="submit">',csrf=true,logged=true}={}){
  const html=`<div class="lang-chooser"><a href="/profile/Fixture">Fixture</a>${logged?'<a href="/logout">Logout</a>':''}</div><form method="post" action="${action}">${csrf?'<input type="hidden" name="csrf_token" value="fixture-token">':''}<select name="${field}"><option value="${value}">${value}</option></select><select name="programTypeId"><option value="54">GNU G++17 7.3.0</option><option value="89">GNU G++20</option></select><textarea name="source" required></textarea>${extra}${button}</form>`;
  const dom=new JSDOM(html,{url,runScripts:'outside-only'}),w=dom.window;
  w.input={contest:4,index:'A',id:'4A',source:'// local fixture only\nint main(){}',language:'89',handle:'Fixture',nonce:'fixture-'+Math.random()};
  const posted=[];let gets=0;
  w.document.querySelector('form').addEventListener('submit',e=>{e.preventDefault();posted.push(Object.fromEntries(new w.FormData(e.target)));});
  w.fetch=async()=>{gets++;return {ok:true,json:async()=>({status:'OK',result:[{id:123}]})};};
  return {w,posted,get gets(){return gets;},snapshot:()=>w.eval(snapshot),send:()=>w.eval('(async()=>{'+dispatch+'})()'),close:()=>w.close()};
}
async function checkNotSent(config,code,mutate){const f=fixture(config);try{mutate?.(f);assert.equal(f.snapshot().readinessError,code);assert.equal(f.snapshot().form,false);assert.equal((await f.send()).error,code);assert.equal(f.posted.length,0);assert.equal(f.gets,0);}finally{f.close();}}

test('both platforms ship exactly the same readiness and dispatch checks',()=>{
  assert.equal(snapshot,'(() => {\n'+raw('formHelpers')+'\n'+raw('snapshotBody')+'\n})()');
  assert.equal(dispatch,raw('formHelpers')+'\n'+raw('dispatchOperation'));
  assert.equal(asset('receipt'),raw('receiptBody'));
  for(const m of swift.matchAll(/case "([A-Z_]+)": return "([^"]+)"/g))assert.equal(submissionMessage(m[1]),m[2]);
});
test('preselected contest URL with empty action is ready and clicks once with exact source/problem/compiler',async()=>{
 const f=fixture();try{assert.equal(f.snapshot().form,true);assert.equal((await f.send()).dispatched,true);assert.equal(f.posted.length,1);assert.equal(f.posted[0].source,f.w.input.source);assert.equal(f.posted[0].submittedProblemIndex,'A');assert.equal(f.posted[0].programTypeId,'89');assert.equal((await f.send()).error,'ALREADY_SENT');assert.equal(f.posted.length,1);}finally{f.close();}
});
test('canonical, query-only, explicit preselected and trailing slash actions are supported',async()=>{
 for(const cfg of [{url:'https://codeforces.com/contest/4/submit'},{action:'?csrf_token=fixture'},{action:'/contest/4/submit/A/'},{action:'/contest/4/submit?locale=en'},{url:'https://codeforces.com/problemset/submit/4/A',field:'submittedProblemCode',value:'4A'},{url:'https://codeforces.com/problemset/submit',field:'submittedProblemIndex',extra:'<input name="contestId" value="4">'}]){const f=fixture(cfg);try{assert.equal(f.snapshot().form,true,JSON.stringify(cfg));assert.equal((await f.send()).dispatched,true);assert.equal(f.posted.length,1);}finally{f.close();}}
});
test('field and button overrides cannot send to another site or unsupported route',async()=>{
 for(const action of ['https://example.org/contest/4/submit','http://codeforces.com/contest/4/submit','https://codeforces.com:444/contest/4/submit','https://user@codeforces.com/contest/4/submit','/enter','/contest/4/submit/A/extra'])await checkNotSent({action},'FORM_ACTION_UNSUPPORTED');
 await checkNotSent({button:'<button type="submit" formaction="https://example.org">Submit</button>'},'FORM_ACTION_UNSUPPORTED');
 await checkNotSent({button:'<button type="submit" formmethod="get">Submit</button>'},'FORM_ACTION_UNSUPPORTED');
});
test('wrong contest, wrong preselected problem, missing contest context and disabled options do not send',async()=>{
 await checkNotSent({action:'/contest/5/submit'},'WRONG_PROBLEM');
 await checkNotSent({action:'/contest/4/submit/B'},'WRONG_PROBLEM');
 await checkNotSent({extra:'<input name="contestId" value="5">'},'WRONG_PROBLEM');
 await checkNotSent({action:'/problemset/submit'},'WRONG_PROBLEM');
 await checkNotSent({value:'B'},'WRONG_PROBLEM');
 await checkNotSent({},'WRONG_PROBLEM',f=>f.w.document.querySelector('[name=submittedProblemIndex] option').disabled=true);
});
test('login, token, verification and disabled submit are distinct from ready form',async()=>{
 await checkNotSent({logged:false},'LOGIN_REQUIRED');
 await checkNotSent({csrf:false},'TOKEN_MISSING');
 await checkNotSent({extra:'<input name="cf-turnstile-response" value="">'},'VERIFICATION_REQUIRED');
 await checkNotSent({button:'<button type="submit" disabled>Submit</button>'},'SUBMIT_UNAVAILABLE');
 const f=fixture({csrf:false,action:'?csrf_token=fixture'});try{assert.equal(f.snapshot().form,true);assert.equal((await f.send()).dispatched,true);}finally{f.close();}
});
test('visible source area alone never means ready; editor-loading and missing language are explicit',async()=>{
 await checkNotSent({extra:'<div class="ace_editor"></div>'},'EDITOR_NOT_READY');
 await checkNotSent({},'FORM_FIELDS_MISSING',f=>f.w.document.querySelector('[name=programTypeId]').remove());
 await checkNotSent({},'FORM_MISSING',f=>f.w.document.querySelector('form').remove());
});
test('API HTTP, JSON and network failures are definitely not sent and can be retried',async()=>{
 for(const fetch of [async()=>({ok:false}),async()=>({ok:true,json:async()=>{throw Error('HTML response')}}),async()=>{throw Error('offline')},async()=>({ok:true,json:async()=>({status:'FAILED'})}),async()=>({ok:true,json:async()=>({status:'OK',result:[{id:'bad'}]})})]){
  const f=fixture();try{f.w.fetch=fetch;assert.equal((await f.send()).error,'BASELINE_UNAVAILABLE');assert.equal(f.posted.length,0);assert.equal(f.w.__pocketSent,undefined);f.w.fetch=async()=>({ok:true,json:async()=>({status:'OK',result:[]})});assert.equal((await f.send()).dispatched,true);}finally{f.close();}
 }
});
test('account/form changes during baseline and unsupported compiler fail before click',async()=>{
 for(const change of [f=>f.w.document.querySelector('[href="/profile/Fixture"]').href='/profile/Other',f=>f.w.document.querySelector('form').action='/contest/9/submit']){const f=fixture();try{f.w.fetch=async()=>{change(f);return{ok:true,json:async()=>({status:'OK',result:[]})}};assert.ok(['ACCOUNT_CHANGED','WRONG_PROBLEM'].includes((await f.send()).error));assert.equal(f.posted.length,0);}finally{f.close();}}
 const f=fixture();try{f.w.input.language='999';assert.equal((await f.send()).error,'LANGUAGE_UNAVAILABLE');assert.equal(f.gets,0);}finally{f.close();}
});
test('simultaneous requests cannot dispatch twice',async()=>{
 const f=fixture();try{let finish;f.w.fetch=()=>new Promise(resolve=>finish=resolve);const first=f.send();assert.equal((await f.send()).error,'ALREADY_SENT');finish({ok:true,json:async()=>({status:'OK',result:[]})});assert.equal((await first).dispatched,true);assert.equal(f.posted.length,1);}finally{f.close();}
});
test('CodeMirror and Ace synchronize exact frozen source; invalid forms and storage failure never click',async()=>{
 for(const type of ['CodeMirror','ace_editor']){const f=fixture({extra:`<div class="${type}"></div>`});try{let value='';const editor={setValue:v=>value=v,getValue:()=>value,save:()=>{}};const node=f.w.document.querySelector('.'+type);if(type==='CodeMirror')node.CodeMirror=editor;else node.env={editor};assert.equal((await f.send()).dispatched,true);assert.equal(value,f.w.input.source);}finally{f.close();}}
 const a=fixture({extra:'<input name="extraRequired" required>'});try{assert.equal((await a.send()).error,'FORM_INVALID');assert.equal(a.posted.length,0);}finally{a.close();}
 const b=fixture();try{b.w.Storage.prototype.setItem=()=>{throw Error('storage failed')};assert.equal((await b.send()).error,'STORAGE_UNAVAILABLE');assert.equal(b.posted.length,0);assert.equal(b.w.__pocketSent,undefined);}finally{b.close();}
});
test('numeric-looking problem indices preserve their leading zero',async()=>{
 const f=fixture({url:'https://codeforces.com/contest/921/submit/01',value:'01'});try{Object.assign(f.w.input,{contest:921,index:'01',id:'921-01'});assert.equal((await f.send()).dispatched,true);assert.equal(f.posted[0].submittedProblemIndex,'01');}finally{f.close();}
});
