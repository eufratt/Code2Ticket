import express, { Router } from 'express';
import { updateProfile } from '../services/auth.js';
import { MAX_PHOTO_BYTES, getPhoto, savePhoto } from '../services/photos.js';
import { uuidSchema } from '../services/giveaways.js';
import {
  getCategoryAffinity, getLeaderboard, getMyFeedback, getNotifications, logActivity,
  markNotificationsRead, submitFeedback, submitGameScore,
} from '../services/features.js';

// Semua endpoint di sini membutuhkan session.
export default function meRoutes({ pool, session, uploadLimit }) {
  const r = Router();
  r.patch('/me', session, async (req, res) => res.json(await updateProfile(pool, req.user, req.body)));
  // Foto profil: JPEG biner (Content-Type: image/jpeg), maks. 150 KB; lebih besar -> 413 sebelum diproses.
  r.put('/me/photo', uploadLimit, session, express.raw({ type: 'image/jpeg', limit: MAX_PHOTO_BYTES }), async (req, res) =>
    res.json(await savePhoto(pool, req.user, req.body, req.is('image/jpeg') ? 'image/jpeg' : null)));
  // Publik (tanpa token): alamat memuat UUID acak dan versi (?v=) berganti saat foto diganti.
  r.get('/users/:id/photo', async (req, res) => {
    const id = uuidSchema.safeParse(req.params.id);
    const photo = id.success ? await getPhoto(pool, id.data) : null;
    if (!photo) return res.status(404).json({ ok: false, error: 'not_found' });
    res.set({
      'Content-Type': photo.content_type,
      'Cache-Control': 'public, max-age=86400',
      ETag: `"${photo.v}"`,
      'Cross-Origin-Resource-Policy': 'cross-origin',
    });
    return res.send(photo.bytes); // Express menjawab 304 bila If-None-Match cocok
  });
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
