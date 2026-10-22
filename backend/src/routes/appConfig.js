import { Router } from 'express';
import { getOrganizerContact } from '../services/appConfig.js';

export default function appConfigRoutes({ pool }) {
  const r = Router();
  // Publik (tanpa session), seperti GET /giveaways; hanya dibatasi limiter global.
  r.get('/organizer', async (_req, res) => res.json(await getOrganizerContact(pool)));
  return r;
}
