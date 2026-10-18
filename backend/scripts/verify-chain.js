// Audit seluruh hash-chain di database (pengganti fn_verify_chain). Exit 1 bila ada block rusak.
import 'dotenv/config';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';
import { verifyChain } from '../src/lib/chain.js';

const pool = createPool(loadConfig());
try {
  const rows = await verifyChain(pool);
  const bad = rows.filter((r) => !r.ok);
  console.log(`${rows.length} block diperiksa, ${bad.length} rusak`);
  for (const b of bad) console.log(`  block ${b.block_index}: ${b.reason}`);
  process.exitCode = bad.length ? 1 : 0;
} finally {
  await pool.end();
}
