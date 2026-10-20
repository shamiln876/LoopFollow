import {test} from 'node:test';
import assert from 'node:assert/strict';
import worker, {validateResult} from './worker.mjs';
import catalog from '../../LoopFollow/Resources/CarnivalFoodGuide.json' with {type:'json'};
const budget = (fetch) => ({idFromName: name => {assert.equal(name,'family-scanner'); return name;}, get: () => ({fetch})});
const env = {OPENAI_API_KEY:'test-only', SCANNER_ACCESS_TOKEN:'x'.repeat(40), SCAN_BUDGET:budget(async () => Response.json({result:'allowed'}))};
const suggestion = {label:'bagel', foodID:catalog.foods[0].id, portions:0.5, uncertainty:'Estimate; verify portion'};
const req = (body, token = env.SCANNER_ACCESS_TOKEN) => new Request('https://example.test/scan',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body)});
test('catalog-only match retains unknowns', () => {
  const result = validateResult({items:[suggestion,{...suggestion,foodID:null,portions:null}]});
  assert.equal(result.items[1].foodID,null); assert.equal(result.sourceSHA256,catalog.sourceSHA256);
});
test('rejects hallucinated IDs, invalid quantities, empty or excessive output', () => {
  for (const x of [{...suggestion,foodID:'invented'}, {...suggestion,portions:0}, {...suggestion,portions:Infinity}, {...suggestion,portions:101}, {...suggestion,label:''}]) assert.throws(()=>validateResult({items:[x]}));
  assert.throws(()=>validateResult({items:[]})); assert.throws(()=>validateResult({items:Array(21).fill(suggestion)}));
});
test('missing setup, wrong token, malformed photo and wrong catalog fail closed', async () => {
  assert.equal((await worker.fetch(req({}),{})).status,503);
  assert.equal((await worker.fetch(req({},'wrong'),env)).status,401);
  assert.equal((await worker.fetch(req({image:'abcd',sourceSHA256:catalog.sourceSHA256}),env)).status,400);
  assert.equal((await worker.fetch(req({image:'/9j/AA==',sourceSHA256:'wrong'}),env)).status,400);
});
test('successful request strips model extras and sends no patient fields', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    assert.equal(url,'https://api.openai.com/v1/responses');
    const body = JSON.parse(options.body); assert.equal(body.store,false); assert.equal(body.text.format.strict,true);
    assert.equal(body.model,'gpt-4.1-mini-2025-04-14'); assert.equal(body.max_output_tokens,3000);
    assert(!JSON.stringify(body).includes('Nightscout'));
    return Response.json({status:'completed',output:[{content:[{type:'output_text',text:JSON.stringify({items:[{...suggestion,carbs:999}]})}]}]});
  };
  try { const response = await worker.fetch(req({image:'/9j/AA==',sourceSHA256:catalog.sourceSHA256}),env); assert.equal(response.status,200); assert.equal((await response.json()).items[0].carbs,undefined); }
  finally {globalThis.fetch = original;}
});
test('missing, exhausted, broken or malformed budget never invokes provider', async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {calls++; throw Error('Must not invoke provider');};
  try {
    for (const [binding, status] of [
      [undefined,503],
      [budget(async()=>Response.json({result:'monthly'},{status:429})),429],
      [budget(async()=>new Response(null,{status:503})),503],
      [budget(async()=>Response.json({result:'unexpected'})),503],
      [budget(async()=>{throw Error('Storage unavailable');}),502]
    ]) assert.equal((await worker.fetch(req({image:'/9j/AA==',sourceSHA256:catalog.sourceSHA256}),{...env,SCAN_BUDGET:binding})).status,status);
    assert.equal(calls,0);
  } finally {globalThis.fetch = original;}
});
test('provider failure retains reservation and does not retry', async () => {
  const original = globalThis.fetch;
  let reserved = 0, calls = 0;
  globalThis.fetch = async () => {calls++; assert.equal(reserved,1); throw Error('Timeout after dispatch');};
  try {
    const response = await worker.fetch(req({image:'/9j/AA==',sourceSHA256:catalog.sourceSHA256}),{...env,OPENAI_MODEL:'expensive-model',SCAN_BUDGET:budget(async()=>{reserved++; return Response.json({result:'allowed'});})});
    assert.equal(response.status,502); assert.equal(calls,1); assert.equal(reserved,1);
  } finally {globalThis.fetch=original;}
});
test('refusal, truncation and provider errors never become empty zero-carb plates', async () => {
  const original = globalThis.fetch;
  try { for (const body of [{status:'incomplete'}, {status:'completed',output:[{content:[{type:'refusal'}]}]}]) {
    globalThis.fetch = async () => Response.json(body);
    assert.equal((await worker.fetch(req({image:'/9j/AA==',sourceSHA256:catalog.sourceSHA256}),env)).status,502);
  }} finally {globalThis.fetch=original;}
});
test('rate limit prevents provider invocation and oversized requests are rejected', async () => {
  assert.equal((await worker.fetch(req({image:'/9j/AA==',sourceSHA256:catalog.sourceSHA256}),{...env,RATE_LIMITER:{limit:async()=>({success:false})}})).status,429);
  const oversized = new Request('https://example.test/scan',{method:'POST',headers:{Authorization:'Bearer '+env.SCANNER_ACCESS_TOKEN,'Content-Type':'application/json','Content-Length':'5000000'},body:'{}'});
  assert.equal((await worker.fetch(oversized,env)).status,413);
});
