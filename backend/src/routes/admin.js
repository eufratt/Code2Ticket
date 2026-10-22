import { Router } from 'express';
import { requireAdmin } from '../middleware/auth.js';
import { upsertGiveaway } from '../services/admin.js';
import { generateCodes, listCodes } from '../services/codes.js';
import { adminRunDraw } from '../services/draw.js';
import { searchGiveaways, uuidSchema } from '../services/giveaways.js';
import { invalid } from '../lib/util.js';

export default function adminRoutes({ pool }) {
  const r = Router();
  r.use(requireAdmin(pool));
  // Semua status (upcoming, active, waiting_draw, drawn), terbaru dulu; GET /giveaways publik hanya yang aktif.
  r.get('/giveaways', async (req, res) => {
    const { limit, offset } = req.query;
    res.json(await searchGiveaways(pool, { limit, offset, status: 'all', sort: 'newest' }, { grouped: false }));
  });
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
