import cors from 'cors';
import express from 'express';
import { rateLimit } from 'express-rate-limit';
import helmet from 'helmet';
import { requireSession } from './middleware/auth.js';
import { HttpError } from './lib/util.js';
import adminRoutes from './routes/admin.js';
import appConfigRoutes from './routes/appConfig.js';
import authRoutes from './routes/auth.js';
import chatRoutes from './routes/chat.js';
import giveawayRoutes from './routes/giveaways.js';
import meRoutes from './routes/me.js';
import internalRoutes from './routes/internal.js';
import ticketRoutes from './routes/tickets.js';

const tooMany = (_req, res) => res.status(429).json({ ok: false, error: 'too_many_requests' });
const limiter = (limit) =>
  rateLimit({ windowMs: 60_000, limit, standardHeaders: 'draft-7', legacyHeaders: false, handler: tooMany });

// logger: hanya method, path (tanpa query), status, durasi. Tidak pernah body/header.
const defaultLog = (line) => console.log(line);

// fetchImpl: hanya untuk tes (menggantikan fetch ke OpenAI).
export function createApp({ pool, config, log = defaultLog, fetchImpl }) {
  const app = express();
  app.disable('x-powered-by');
  if (config.TRUST_PROXY > 0) app.set('trust proxy', config.TRUST_PROXY);

  app.use(helmet());
  app.use(
    cors({
      origin: (origin, cb) => cb(null, !origin || config.corsOrigins.includes(origin)),
      allowedHeaders: ['Authorization', 'Content-Type'],
      methods: ['GET', 'POST', 'PATCH', 'OPTIONS'],
    }),
  );
  app.use((req, res, next) => {
    const t = Date.now();
    const path = req.originalUrl.split('?')[0];
    res.on('finish', () => log(`${req.method} ${path} ${res.statusCode} ${Date.now() - t}ms`));
    next();
  });
  app.use(limiter(config.RATE_LIMIT_MAX));
  app.use(express.json({ limit: '100kb' }));

  const deps = { pool, config, log, fetchImpl, session: requireSession(pool), uploadLimit: limiter(config.UPLOAD_RATE_LIMIT_MAX ?? 10) };
  app.use('/auth', limiter(config.AUTH_RATE_LIMIT_MAX), authRoutes(deps));
  app.use('/app-config', appConfigRoutes(deps));
  app.use('/giveaways', giveawayRoutes(deps));
  app.use('/admin', adminRoutes(deps));
  app.use('/internal', internalRoutes(deps));
  app.use('/', ticketRoutes(deps));
  app.use('/', meRoutes(deps));
  app.use('/', chatRoutes(deps));

  app.use((_req, res) => res.status(404).json({ ok: false, error: 'not_found' }));
  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    if (err instanceof HttpError) return res.status(err.status).json({ ok: false, error: err.code });
    if (err.type === 'entity.parse.failed') return res.status(400).json({ ok: false, error: 'invalid_json' });
    if (err.type === 'entity.too.large') return res.status(413).json({ ok: false, error: 'payload_too_large' });
    // Jangan mencatat message/stack: pesan driver dapat memuat nilai (hash, token) dari query.
    log(`ERROR ${err.code ?? err.name}`);
    return res.status(500).json({ ok: false, error: 'internal_error' });
  });
  return app;
}

