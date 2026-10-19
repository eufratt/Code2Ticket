import { Router } from 'express';
import { createChatService } from '../services/chat.js';

// POST /chat (wajib sesi). Galat bisnis HTTP 200 {ok:false,error}; sesi tidak valid 401 oleh middleware.
export default function chatRoutes({ pool, config, session, log, fetchImpl }) {
  const r = Router();
  const chat = createChatService({ pool, config, log, fetchImpl });
  r.post('/chat', session, async (req, res) => res.json(await chat(req.user, req.body)));
  return r;
}
