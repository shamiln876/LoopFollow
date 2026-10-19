import {test} from 'node:test';
import assert from 'node:assert/strict';
import {reserveScan, ScanBudget} from './budget.mjs';

// Serial transactional test double. Production uses Cloudflare's durable storage.
function storage(initial) {
  let value = initial, tail = Promise.resolve();
  return {
    transaction(fn) {
      const result = tail.then(async () => {
        let pending = structuredClone(value);
        const result = await fn({get:async()=>structuredClone(pending),put:async(_,v)=>{pending=structuredClone(v);}});
        value = pending;
        return result;
      });
      tail = result.catch(()=>{});
      return result;
    },
    read:()=>structuredClone(value)
  };
}
const at = day => new Date(`2026-10-${String(day).padStart(2,'0')}T12:00:00Z`);

test('100 concurrent attempts admit only ten per UTC day', async () => {
  const db = storage();
  const results = await Promise.all(Array.from({length:100},()=>reserveScan(db,at(1))));
  assert.equal(results.filter(x=>x==='allowed').length,10);
  assert.equal(results.filter(x=>x==='daily').length,90);
  assert.deepEqual(db.read(),{day:'2026-10-01',month:'2026-10',daily:10,monthly:10});
});
test('monthly limit survives new days and recreation; next UTC month resets', async () => {
  const db = storage();
  for (let day=1;day<=10;day++) {
    for (let n=0;n<10;n++) assert.equal(await reserveScan(db,at(day)),'allowed');
  }
  const restarted = storage(db.read());
  assert.equal(await reserveScan(restarted,at(11)),'monthly');
  assert.equal(await reserveScan(restarted,new Date('2026-11-01T00:00:00Z')),'allowed');
  assert.equal(restarted.read().monthly,1);
});
test('corrupt storage, backward clock and failed writes fail closed', async () => {
  for (const invalid of [null,{}, {day:'2026-10-18',month:'2026-10',daily:-1,monthly:0},
    {day:'2026-10-18',month:'2026-10',daily:2,monthly:1}]) {
    await assert.rejects(reserveScan(storage(invalid),at(18)));
  }
  const db=storage(); await reserveScan(db,at(18));
  await assert.rejects(reserveScan(db,at(17)));
  await assert.rejects(reserveScan({transaction:async fn=>fn({get:async()=>undefined,put:async()=>{throw Error('disk');}})},at(18)));
});
test('Durable Object refuses invalid routes and returns unavailable on storage failure', async () => {
  const object = new ScanBudget({storage:{transaction:async()=>{throw Error('unavailable');}}});
  assert.equal((await object.fetch(new Request('https://budget.internal/reserve'))).status,404);
  assert.equal((await object.fetch(new Request('https://budget.internal/reserve',{method:'POST'}))).status,503);
});
