import { Router } from 'express';
import { bearerToken } from '../middleware/auth.js';
import * as auth from '../services/auth.js';
import { userJson } from '../services/users.js';
import { ok } from '../lib/util.js';

export default function authRoutes({ pool, session }) {
  const r = Router();
  r.post('/register', async (req, res) => res.json(await auth.register(pool, req.body)));
  r.post('/salt', async (req, res) => res.json(await auth.getSalt(pool, req.body)));
  r.post('/login', async (req, res) => res.json(await auth.login(pool, req.body)));
  // Logout tidak memvalidasi: token apa pun dijawab ok (sama seperti rpc_logout).
  r.post('/logout', async (req, res) => res.json(await auth.logout(pool, bearerToken(req))));
  r.get('/me', session, async (req, res) => res.json(ok({ user: await userJson(pool, req.user) })));
  return r;
}
