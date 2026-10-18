import { Router } from 'express';
import { runDueDraws } from '../services/draw.js';
import { timingSafeEqualStr } from '../lib/util.js';

// Pemicu scheduler dari luar (cron host / layanan terjadwal). Dilindungi header X-Tick-Secret.
export default function internalRoutes({ pool, config }) {
  const r = Router();
  r.post('/tick', async (req, res) => {
    if (!config.TICK_SECRET) return res.status(404).json({ ok: false, error: 'not_found' }); // dimatikan
    const given = req.get('x-tick-secret');
    if (!given || !timingSafeEqualStr(given, config.TICK_SECRET)) {
      return res.status(403).json({ ok: false, error: 'forbidden' });
    }
    res.json({ ok: true, drawn: await runDueDraws(pool) });
  });
  return r;
}
