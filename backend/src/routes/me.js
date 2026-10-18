import { Router } from 'express';
import { updateProfile } from '../services/auth.js';
import {
  getCategoryAffinity, getLeaderboard, getMyFeedback, getNotifications, logActivity,
  markNotificationsRead, submitFeedback, submitGameScore,
} from '../services/features.js';

// Semua endpoint di sini membutuhkan session.
export default function meRoutes({ pool, session }) {
  const r = Router();
  r.patch('/me', session, async (req, res) => res.json(await updateProfile(pool, req.user, req.body)));
  r.get('/me/affinity', session, async (req, res) => res.json(await getCategoryAffinity(pool, req.user)));
  r.post('/activity', session, async (req, res) => res.json(await logActivity(pool, req.user, req.body)));
  r.post('/game/scores', session, async (req, res) => res.json(await submitGameScore(pool, req.user, req.body)));
  r.get('/game/leaderboard', session, async (req, res) => res.json(await getLeaderboard(pool, req.query)));
  r.get('/notifications', session, async (req, res) => res.json(await getNotifications(pool, req.user, req.query)));
  r.post('/notifications/read', session, async (req, res) => res.json(await markNotificationsRead(pool, req.user, req.body)));
  r.post('/feedback', session, async (req, res) => res.json(await submitFeedback(pool, req.user, req.body)));
  r.get('/feedback', session, async (req, res) => res.json(await getMyFeedback(pool, req.user)));
  return r;
}
