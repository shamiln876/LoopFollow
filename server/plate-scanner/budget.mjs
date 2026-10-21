// One persistent family-wide counter, shared across devices and Worker locations.
// Count attempts BEFORE provider dispatch. Never refund uncertain/failed requests.
export const DAILY_SCAN_LIMIT = 10;
export const MONTHLY_SCAN_LIMIT = 100;

export async function reserveScan(storage, now = new Date()) {
  const day = now.toISOString().slice(0, 10);
  const month = day.slice(0, 7);
  return storage.transaction(async txn => {
    const previous = await txn.get('scan-quota');
    if (previous !== undefined && (!previous ||
      !/^\d{4}-\d{2}-\d{2}$/.test(previous.day) ||
      !/^\d{4}-\d{2}$/.test(previous.month) ||
      previous.day.slice(0, 7) !== previous.month ||
      !Number.isSafeInteger(previous.daily) || previous.daily < 0 ||
      !Number.isSafeInteger(previous.monthly) || previous.monthly < previous.daily)) {
      throw Error('Invalid quota state');
    }
    // A backward clock must not reset a spent allowance.
    if (previous && day < previous.day) throw Error('Invalid quota clock');
    const daily = previous?.day === day ? previous.daily : 0;
    const monthly = previous?.month === month ? previous.monthly : 0;
    if (monthly >= MONTHLY_SCAN_LIMIT) return 'monthly';
    if (daily >= DAILY_SCAN_LIMIT) return 'daily';
    await txn.put('scan-quota', {day, month, daily: daily + 1, monthly: monthly + 1});
    return 'allowed';
  });
}

// SQLite-backed Durable Object; only counts/dates are stored, never photos.
export class ScanBudget {
  constructor(state) { this.storage = state.storage; }
  async fetch(request) {
    if (request.method !== 'POST' || new URL(request.url).pathname !== '/reserve') {
      return new Response(null, {status: 404});
    }
    try {
      const result = await reserveScan(this.storage);
      return Response.json({result}, {status: result === 'allowed' ? 200 : 429});
    } catch {
      return new Response(null, {status: 503});
    }
  }
}
