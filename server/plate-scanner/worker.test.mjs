import {test} from 'node:test';
import assert from 'node:assert/strict';
import worker, {validateResult} from './worker.mjs';
import catalog from '../../LoopFollow/Resources/CarnivalFoodGuide.json' with {type:'json'};
const env = {OPENAI_API_KEY:'test-only', SCANNER_ACCESS_TOKEN:'x'.repeat(40)};
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
    assert(!JSON.stringify(body).includes('Nightscout'));
    return Response.json({status:'completed',output:[{content:[{type:'output_text',text:JSON.stringify({items:[{...suggestion,carbs:999}]})}]}]});
  };
  try { const response = await worker.fetch(req({image:'/9j/AA==',sourceSHA256:catalog.sourceSHA256}),env); assert.equal(response.status,200); assert.equal((await response.json()).items[0].carbs,undefined); }
  finally {globalThis.fetch = original;}
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
