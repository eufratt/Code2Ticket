import { z } from 'zod';

const bool = z.enum(['true', 'false']).transform((v) => v === 'true');

const schema = z.object({
  NODE_ENV: z.string().default('development'),
  PORT: z.coerce.number().int().min(0).max(65535).default(3000),
  DATABASE_URL: z.string().min(1),
  DATABASE_SSL: z.enum(['disable', 'require', 'verify-full']).default('disable'),
  DB_POOL_MAX: z.coerce.number().int().min(1).max(100).default(10),
  CORS_ORIGINS: z.string().default(''),
  TICK_SECRET: z.string().default('').refine((v) => v === '' || v.length >= 16, 'TICK_SECRET minimal 16 karakter'),
  SCHEDULER_ENABLED: bool.default(true),
  RATE_LIMIT_MAX: z.coerce.number().int().min(1).default(300),
  AUTH_RATE_LIMIT_MAX: z.coerce.number().int().min(1).default(20),
  UPLOAD_RATE_LIMIT_MAX: z.coerce.number().int().min(1).default(10),
  TRUST_PROXY: z.coerce.number().int().min(0).default(0),
  // Asisten AI (POST /chat). Kosong = fitur mati (jawaban ai_not_configured). JANGAN pernah di-log.
  OPENAI_API_KEY: z.string().default(''),
  OPENAI_MODEL: z.string().default(''),
  AI_DAILY_LIMIT_PER_USER: z.coerce.number().int().min(1).default(30),
  AI_RATE_PER_MINUTE: z.coerce.number().int().min(1).default(8),
  OPENAI_TIMEOUT_MS: z.coerce.number().int().min(1000).max(60000).default(20000),
});

// Hanya mengembalikan nilai terurai; tidak pernah mencetak isi env.
export function loadConfig(env = process.env) {
  const r = schema.safeParse(env);
  if (!r.success) {
    const keys = [...new Set(r.error.issues.map((i) => i.path.join('.')))].join(', ');
    throw new Error(`Konfigurasi .env tidak valid: ${keys}`);
  }
  const c = r.data;
  return {
    ...c,
    corsOrigins: c.CORS_ORIGINS.split(',').map((s) => s.trim()).filter(Boolean),
  };
}
