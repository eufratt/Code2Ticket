import { Router } from 'express';
import { getGiveaway, getVerificationData, getWinners, searchGiveaways, uuidSchema } from '../services/giveaways.js';
import { getAnchors } from '../services/anchor.js';
import { invalid } from '../lib/util.js';

export default function giveawayRoutes({ pool, config }) {
  const r = Router();
  // Publik (tanpa session), seperti rpc_search_giveaways / rpc_get_winners / rpc_get_verification_data.
  r.get('/', async (req, res) => res.json(await searchGiveaways(pool, req.query)));
  // 404 bila tidak ada (id yang bukan UUID dianggap tidak ada).
  r.get('/:id', async (req, res) => {
    const id = uuidSchema.safeParse(req.params.id);
    const g = id.success ? await getGiveaway(pool, id.data) : null;
    if (!g) return res.status(404).json({ ok: false, error: 'not_found' });
    res.json(g);
  });
  r.get('/:id/winners', async (req, res) => {
    const id = uuidSchema.safeParse(req.params.id);
    res.json(id.success ? await getWinners(pool, id.data) : invalid('id'));
  });
  r.get('/:id/verification', async (req, res) => {
    const id = uuidSchema.safeParse(req.params.id);
    res.json(id.success ? await getVerificationData(pool, id.data) : invalid('id'));
  });
  // Jangkar blockchain per blok (tx_hash, status, explorer_url, rpc_url publik tanpa key).
  r.get('/:id/anchors', async (req, res) => {
    const id = uuidSchema.safeParse(req.params.id);
    res.json(id.success ? await getAnchors(pool, config, id.data) : invalid('id'));
  });
  return r;
}
