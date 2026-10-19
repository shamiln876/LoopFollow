// Run from the repository root with Miniflare 5.20261012.1-beta (bundled with Wrangler 4.151.1).
// MINIFLARE_MODULE can point at the installed package's absolute entrypoint.
const {Miniflare,convertV4MiniflareOptions}=await import(process.env.MINIFLARE_MODULE || 'miniflare');
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import assert from 'node:assert/strict';
const source=(await readFile('server/plate-scanner/budget.mjs','utf8')).replaceAll('export const ', 'const ');
const persist=await mkdtemp('/private/tmp/plate-budget-persist-');
const options={modules:true,compatibilityDate:'2025-10-01',durableObjects:{BUDGET:{className:'ScanBudget',useSQLite:true}},resourcePersistencePath:persist,script:source+'\nexport default {async fetch(request,env) {return env.BUDGET.get(env.BUDGET.idFromName("family-scanner")).fetch(request);}}'};
let runtime=new Miniflare(convertV4MiniflareOptions(options));
try {
 const result=await Promise.all(Array.from({length:100},()=>runtime.dispatchFetch('https://test/reserve',{method:'POST'})));
 assert.equal(result.filter(r=>r.status===200).length,10);
 assert.equal(result.filter(r=>r.status===429).length,90);
 await runtime.dispose();
 runtime=new Miniflare(convertV4MiniflareOptions(options));
 assert.equal((await runtime.dispatchFetch('https://test/reserve',{method:'POST'})).status,429);
 console.log('PASS: actual local Workers runtime, SQLite storage, 100 simultaneous calls allow exactly 10; limit survives runtime restart. No OpenAI requests.');
} finally {await runtime.dispose(); await rm(persist,{recursive:true,force:true});}
