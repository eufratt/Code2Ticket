import cron from 'node-cron';
import { cleanup, runDueDraws } from './draw.js';

// Pengganti 03_cron.sql: draw jatuh tempo tiap menit, cleanup harian 20:00 UTC (03:00 WIB).
export function startScheduler({ pool, log = () => {} }) {
  let busy = false;
  const guarded = (name, fn) => async () => {
    if (name === 'draws') {
      if (busy) return; // jangan menumpuk bila satu putaran lebih lama dari semenit
      busy = true;
    }
    try {
      await fn(pool);
    } catch (e) {
      log(`scheduler ${name} gagal: ${e.code ?? e.name}`);
    } finally {
      if (name === 'draws') busy = false;
    }
  };
  const tasks = [
    cron.schedule('* * * * *', guarded('draws', runDueDraws), { timezone: 'UTC' }),
    cron.schedule('0 20 * * *', guarded('cleanup', cleanup), { timezone: 'UTC' }),
  ];
  return { stop: () => tasks.forEach((t) => t.stop()) };
}
