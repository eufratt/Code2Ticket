import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { withTx } from '../db.js';
import { TOKEN_RE, cpLen, fail, ok, parseInput, pgTrim, randomHex, sha256Hex } from '../lib/util.js';
import { userJson } from './users.js';

const BCRYPT_COST = 10;
const MAX_FAILED = 5;
const LOCK_SECONDS = 15 * 60;

const registerSchema = z.object({
  username: z.string().transform(pgTrim).pipe(z.string().regex(/^[A-Za-z0-9_]{4,20}$/)),
  email: z.string().transform((s) => pgTrim(s).toLowerCase()).pipe(z.string().max(254).regex(/^[^@\s]+@[^@\s]+\.[^@\s]+$/i)),
  full_name: z.string().transform(pgTrim).pipe(z.string().refine((s) => cpLen(s) >= 1 && cpLen(s) <= 100)),
  // Format yang dibuat app (16 byte acak -> 32 hex huruf kecil), sama dengan salt palsu di getSalt, supaya salt tidak membedakan akun asli.
  salt: z.string().regex(/^[0-9a-f]{32}$/),
  password_hash: z.string().regex(TOKEN_RE),
});

// Identifier tak valid diperlakukan sebagai '' (seperti coalesce di SQL lama).
const identifierOf = (v) => pgTrim(z.string().max(254).catch('').parse(v)).toLowerCase();

let dummyHash;
const getDummyHash = () => (dummyHash ??= bcrypt.hashSync('dummy-for-timing', BCRYPT_COST));

export async function register(pool, body) {
  const p = parseInput(registerSchema, body);
  if (p.error) return p.error;
  const { username, email, full_name, salt, password_hash } = p.data;
  const bc = await bcrypt.hash(password_hash, BCRYPT_COST);
  try {
    const r = await pool.query(
      'insert into users(username, email, full_name, salt, password_hash) values ($1,$2,$3,$4,$5) returning id',
      [username, email, full_name, salt, bc],
    );
    return ok({ user_id: r.rows[0].id });
  } catch (e) {
    if (e.code === '23505') return fail(e.constraint === 'users_email_uq' ? 'email_taken' : 'username_taken');
    throw e;
  }
}

// Salt asli, atau salt palsu konsisten (HMAC) agar keberadaan akun tidak dapat ditebak.
export async function getSalt(pool, body) {
  const ident = identifierOf(body?.identifier);
  // Kedua query selalu dijalankan agar akun ada/tidak ada sama kerjanya.
  const r = await pool.query('select salt from users where lower(username) = $1 or lower(email) = $1 limit 1', [ident]);
  const k = await pool.query("select value from app_config where key = 'fake_salt_key'");
  const salt = r.rows[0]?.salt ?? crypto.createHmac('sha256', k.rows[0].value).update(ident, 'utf8').digest('hex').slice(0, 32);
  return ok({ salt });
}

export async function login(pool, body) {
  const ident = identifierOf(body?.identifier);
  const hash = body?.password_hash;
  if (ident === '' || typeof hash !== 'string' || !TOKEN_RE.test(hash)) return fail('invalid_credentials');

  const u = (await pool.query('select * from users where lower(username) = $1 or lower(email) = $1 limit 1', [ident])).rows[0];
  // Percobaan dihitung per akun (username dan email berbagi hitungan)
  const key = u ? `u:${u.id}` : ident;

  return withTx(pool, async (c) => {
    await c.query('insert into login_attempts(identifier) values ($1) on conflict do nothing', [key]);
    const la = (
      await c.query(
        `select failed_count, locked_until,
                coalesce(locked_until > now(), false) as is_locked,
                ceil(extract(epoch from (locked_until - now())))::int as retry
           from login_attempts where identifier = $1 for update`,
        [key],
      )
    ).rows[0];
    let failed = la.failed_count;

    if (la.is_locked) return fail('locked', { retry_after_seconds: la.retry });
    if (la.locked_until) {
      await c.query('update login_attempts set failed_count = 0, locked_until = null where identifier = $1', [key]);
      failed = 0;
    }

    // Samakan waktu respons untuk akun yang tidak ada
    let good = false;
    if (u) good = await bcrypt.compare(hash, u.password_hash);
    else await bcrypt.compare(hash, getDummyHash());

    if (!good) {
      failed += 1;
      if (failed >= MAX_FAILED) {
        await c.query(
          `update login_attempts set failed_count = 0, locked_until = now() + make_interval(secs => $2), last_attempt_at = now()
            where identifier = $1`,
          [key, LOCK_SECONDS],
        );
        return fail('locked', { retry_after_seconds: LOCK_SECONDS });
      }
      await c.query('update login_attempts set failed_count = $2, last_attempt_at = now() where identifier = $1', [key, failed]);
      return fail('invalid_credentials', { attempts_left: MAX_FAILED - failed });
    }

    await c.query('delete from login_attempts where identifier = $1', [key]);
    const token = randomHex(32);
    const s = await c.query(
      "insert into sessions(user_id, token_hash, expires_at) values ($1, $2, now() + interval '7 days') returning expires_at",
      [u.id, sha256Hex(token)],
    );
    return ok({ token, expires_at: s.rows[0].expires_at, user: await userJson(c, u) });
  });
}

export async function logout(pool, token) {
  if (typeof token === 'string' && TOKEN_RE.test(token)) {
    await pool.query('update sessions set is_valid = false where token_hash = $1', [sha256Hex(token)]);
  }
  return ok();
}

export async function updateProfile(pool, u, body) {
  const schema = z.object({
    full_name: z.string().nullish().transform((s) => pgTrim(s ?? u.full_name)).pipe(z.string().refine((s) => cpLen(s) >= 1 && cpLen(s) <= 100)),
    photo_url: z.string().refine((s) => cpLen(s) <= 500).nullish(),
  });
  const p = parseInput(schema, body);
  if (p.error) return p.error;
  const r = await pool.query(
    'update users set full_name = $2, photo_url = coalesce($3, photo_url) where id = $1 returning *',
    [u.id, p.data.full_name, p.data.photo_url ?? null],
  );
  return ok({ user: await userJson(pool, r.rows[0]) });
}
