import { adminUser, sessionUser } from '../services/users.js';
import { invalidSession } from '../lib/util.js';

export function bearerToken(req) {
  const m = /^Bearer (\S+)$/i.exec(req.get('authorization') ?? '');
  return m ? m[1] : null;
}

export const requireSession = (pool) => async (req, _res, next) => {
  const token = bearerToken(req);
  if (!token) throw invalidSession();
  req.user = await sessionUser(pool, token);
  next();
};

export const requireAdmin = (pool) => async (req, _res, next) => {
  const token = bearerToken(req);
  if (!token) throw invalidSession();
  req.user = await adminUser(pool, token);
  next();
};
