import { Router } from 'express';
import { requireAdmin } from '../middleware/auth.js';
import { upsertGiveaway } from '../services/admin.js';
import { generateCodes, listCodes } from '../services/codes.js';
import { adminRunDraw } from '../services/draw.js';
import { uuidSchema } from '../services/giveaways.js';
import { invalid } from '../lib/util.js';

export default function adminRoutes({ pool }) {
  const r = Router();
  r.use(requireAdmin(pool));
  // Buat (tanpa id) atau ubah (dengan id) giveaway, seperti rpc_admin_upsert_giveaway.
  r.post('/giveaways', async (req, res) => res.json(await upsertGiveaway(pool, req.user, req.body)));

  r.post('/giveaways/:id/codes', async (req, res) => {
    const id = uuidSchema.safeParse(req.params.id);
    res.json(id.success ? await generateCodes(pool, id.data, req.body) : invalid('id'));
  });
  r.get('/giveaways/:id/codes', async (req, res) => {
    const id = uuidSchema.safeParse(req.params.id);
    res.json(id.success ? await listCodes(pool, id.data) : invalid('id'));
  });
  // Mode demo: draw yang sama dengan scheduler, trigger 'admin_demo'.
  r.post('/giveaways/:id/draw', async (req, res) => {
    const id = uuidSchema.safeParse(req.params.id);
    res.json(id.success ? await adminRunDraw(pool, id.data) : invalid('id'));
  });
  return r;
}
