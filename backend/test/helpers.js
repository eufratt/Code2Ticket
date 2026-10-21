import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { createPool } from '../src/db.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const SCHEMA_DIR = process.env.DB_SCHEMA_DIR ?? path.resolve(HERE, '../db');
export const BACKEND_SQL = path.resolve(HERE, '../db/06_backend.sql');
export const PHOTOS_SQL = path.resolve(HERE, '../db/07_user_photos.sql');
export const PRIZE_IDR_SQL = path.resolve(HERE, '../db/08_prize_value_idr.sql');
export const PARTICIPATION_SQL = path.resolve(HERE, '../db/09_giveaway_participation.sql');
export const REDEEM_GEO_SQL = path.resolve(HERE, '../db/10_redeem_geo_restricted.sql');
const BASE_URL = process.env.TEST_PG_URL ?? 'postgres://postgres@127.0.0.1:54329';

export const sha = (s) => crypto.createHash('sha256').update(s, 'utf8').digest('hex');
// Kontrak klien: PBKDF2-HMAC-SHA256(password, salt UTF-8, 10.000 iterasi, 32 byte) -> hex
export const clientHash = (password, salt) => crypto.pbkdf2Sync(password, salt, 10_000, 32, 'sha256').toString('hex');

// Database uji baru per file tes: shim role Supabase + 01_schema.sql + 06_backend.sql + 07 + 08.
export async function createTestDb(name, migrations = [BACKEND_SQL, PHOTOS_SQL, PRIZE_IDR_SQL, PARTICIPATION_SQL, REDEEM_GEO_SQL]) {
  const dbName = `c2t_node_${name}`;
  const admin = new pg.Client({ connectionString: `${BASE_URL}/postgres` });
  await admin.connect();
  await admin.query(`drop database if exists ${dbName} with (force)`);
  await admin.query(`create database ${dbName}`);
  await admin.end();
  const url = `${BASE_URL}/${dbName}`;
  const c = new pg.Client({ connectionString: url });
  await c.connect();
  const shim = fs.existsSync(path.join(SCHEMA_DIR, '00_supabase_shim.sql'))
    ? path.join(SCHEMA_DIR, '00_supabase_shim.sql')
    : path.join(SCHEMA_DIR, 'tests/00_supabase_shim.sql');
  for (const f of [shim, path.join(SCHEMA_DIR, '01_schema.sql'), ...migrations]) {
    await c.query(fs.readFileSync(f, 'utf8'));
  }
  await c.end();
  return url;
}

export const testConfig = (url, over = {}) => ({
  NODE_ENV: 'test', PORT: 0, DATABASE_URL: url, DATABASE_SSL: 'disable', DB_POOL_MAX: 20,
  corsOrigins: ['http://allowed.example'], TICK_SECRET: 'tick-secret-for-tests-0123456789',
  SCHEDULER_ENABLED: false, RATE_LIMIT_MAX: 100000, AUTH_RATE_LIMIT_MAX: 100000, UPLOAD_RATE_LIMIT_MAX: 100000, TRUST_PROXY: 0, ...over,
});

// Konteks tes: aplikasi di atas pool, koneksi superuser (su) dan koneksi role anon.
export async function createContext(name, over = {}) {
  const url = await createTestDb(name);
  const config = testConfig(url, over);
  const pool = createPool(config);
  const app = createApp({ pool, config, log: () => {} });
  const su = new pg.Client({ connectionString: url });
  await su.connect();
  const anon = new pg.Client({ connectionString: url });
  await anon.connect();
  await anon.query('set role anon');
  return {
    app, pool, su, anon, config, url,
    async close() {
      await anon.end();
      await su.end();
      await pool.end();
    },
  };
}

// Panggilan HTTP; mengembalikan {status, body}.
export async function call(app, method, url, { token, body, query, headers } = {}) {
  let r = request(app)[method](url);
  if (token) r = r.set('Authorization', `Bearer ${token}`);
  for (const [k, v] of Object.entries(headers ?? {})) r = r.set(k, v);
  if (query) r = r.query(query);
  if (body !== undefined) r = r.send(body);
  const res = await r;
  return { status: res.status, body: res.body };
}

// getApp: fungsi, karena app baru ada setelah beforeAll.
export const makeApi = (getApp) => {
  const f = (m) => async (url, opts) => (await call(getApp(), m, url, opts)).body;
  return { get: f('get'), post: f('post'), patch: f('patch'), raw: (m, url, opts) => call(getApp(), m, url, opts) };
};

export async function register(api, username, email, password, name = 'Tester') {
  const salt = crypto.randomBytes(16).toString('hex');
  return api.post('/auth/register', {
    body: { username, email, full_name: name, salt, password_hash: clientHash(password, salt) },
  });
}

export async function login(api, ident, password) {
  const { salt } = await api.post('/auth/salt', { body: { identifier: ident } });
  return api.post('/auth/login', { body: { identifier: ident, password_hash: clientHash(password, salt) } });
}

const iso = (offsetMs) => new Date(Date.now() + offsetMs).toISOString();
export const HOUR = 3_600_000;

export function giveawayBody({
  title = 'Tech Prize', start = -HOUR, end = HOUR, draw = 2 * HOUR, winners = 2, maxTickets = 10,
  category = 'tech', lat = -6.2, lng = 106.8, ...extra
} = {}) {
  return {
    title, category, prize_name: 'Laptop', prize_value_idr: 5_000_000, how_to_participate: 'Ikuti akun penyelenggara dan cari kode di unggahan.', latitude: lat, longitude: lng,
    organizer: 'Acme', description: 'desc', start_at: iso(start), end_at: iso(end), draw_at: iso(draw),
    winner_count: winners, max_tickets_per_user: maxTickets, ...extra,
  };
}
export const mkGiveaway = (api, token, opts) => api.post('/admin/giveaways', { token, body: giveawayBody(opts) });

export async function genCodes(api, token, gid, n) {
  const body = { count: n };
  const r = await api.post(`/admin/giveaways/${gid}/codes`, { token, body });
  return r.codes;
}

export const redeem = (api, token, code, lat, lng) =>
  api.post('/codes/redeem', { token, body: { code, ...(lat !== undefined ? { lat, lng } : {}) } });

// ---- Implementasi verifikasi independen (port dari test_m1.py: block_hash, pick_winners, verify)
export function blockHash(b) {
  const s = b.block_type === 'commit'
    ? `C|${b.block_index}|${b.giveaway_id}|${b.seed_hash}|${b.winner_count}|${b.ts_ms}|${b.previous_hash}`
    : `R|${b.block_index}|${b.giveaway_id}|${b.draw_id}|${b.seed}|${b.total_tickets}|${b.tickets_hash}|${b.winning_tickets}|${b.ts_ms}|${b.previous_hash}`;
  return sha(s);
}

export function pickWinners(seed, gid, tickets, k) {
  const th = sha(tickets.map(([n, o]) => `${n}:${o}`).join(','));
  let pool = [...tickets];
  const win = [];
  let j = 0;
  while (win.length < k && pool.length) {
    const h = crypto.createHash('sha256').update(`${seed}:${gid}:${th}:${j}`).digest();
    let v = 0n;
    for (const byte of h.subarray(0, 7)) v = (v << 8n) | BigInt(byte);
    const [n, o] = pool[Number(v % BigInt(pool.length))];
    win.push(n);
    pool = pool.filter((t) => t[1] !== o);
    j += 1;
  }
  return [th, win];
}

export function verify(data) {
  const chain = data.chain;
  let prev = '0'.repeat(64);
  for (const b of chain) {
    if (b.previous_hash !== prev) return [false, 'rantai hash tidak cocok (previous_hash)'];
    if (blockHash(b) !== b.block_hash) return [false, 'rantai hash tidak cocok (block_hash)'];
    prev = b.block_hash;
  }
  const gid = data.giveaway.id;
  const commit = chain.find((b) => b.giveaway_id === gid && b.block_type === 'commit');
  const result = chain.find((b) => b.giveaway_id === gid && b.block_type === 'result');
  if (!commit) return [false, 'commit block tidak ada'];
  if (data.first_ticket_ms != null && commit.ts_ms > data.first_ticket_ms) return [false, 'commit dibuat setelah tiket'];
  if (!result) return [true, 'belum di-draw (seed masih terkunci)'];
  if (sha(result.seed) !== commit.seed_hash) return [false, 'seed tidak sesuai commitment'];
  const [th, win] = pickWinners(result.seed, gid, data.tickets, commit.winner_count);
  if (th !== result.tickets_hash) return [false, 'tickets_hash tidak cocok'];
  if (win.join(',') !== result.winning_tickets) return [false, 'pemenang tidak cocok'];
  return [true, 'valid'];
}

export const sqlstateOf = async (fn) => {
  try {
    await fn();
  } catch (e) {
    return e.code;
  }
  return null;
};
