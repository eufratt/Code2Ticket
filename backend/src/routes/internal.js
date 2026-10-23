import { Router } from 'express';
import { runDueDraws, runMaintenance } from '../services/draw.js';
import { kickAnchor } from '../services/anchor.js';
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
    const drawn = await runDueDraws(pool);
    await runMaintenance(pool).catch(() => {}); // gagal bersih-bersih tidak boleh menggagalkan tick
    kickAnchor(); // Render bisa tertidur: tick juga membangunkan antrean jangkar (tidak ditunggu)
    res.json({ ok: true, drawn });
  });
  return r;
}
