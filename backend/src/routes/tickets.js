import { Router } from 'express';
import { getMyTickets, redeemCode } from '../services/redeem.js';

export default function ticketRoutes({ pool, session }) {
  const r = Router();
  r.post('/codes/redeem', session, async (req, res) => res.json(await redeemCode(pool, req.user, req.body)));
  r.get('/tickets', session, async (req, res) => res.json(await getMyTickets(pool, req.user)));
  return r;
}
