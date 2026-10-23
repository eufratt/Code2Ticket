import 'dotenv/config';
import { createApp } from './app.js';
import { loadConfig } from './config.js';
import { createPool } from './db.js';
import { startScheduler } from './services/scheduler.js';
import { startAnchor, stopAnchor } from './services/anchor.js';

const log = (line) => console.log(`${new Date().toISOString()} ${line}`);

const config = loadConfig();
const pool = createPool(config);
const app = createApp({ pool, config, log });
const scheduler = config.SCHEDULER_ENABLED ? startScheduler({ pool, log }) : null;
startAnchor({ pool, config, log }); // null (mati) bila ANCHOR_ENABLED bukan true atau konfigurasi kurang

const server = app.listen(config.PORT, () => log(`Code2Ticket backend di port ${config.PORT}`));

let closing = false;
async function shutdown() {
  if (closing) return;
  closing = true;
  scheduler?.stop();
  stopAnchor();
  server.close(async () => {
    await pool.end().catch(() => {});
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
