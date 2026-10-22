import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { clientHash, createContext, login, makeApi, register, testConfig } from './helpers.js';

describe('keamanan HTTP', () => {
  const real = {};
  const logs = [];
  const api = makeApi(() => real.app);
  let strict;
  beforeAll(async () => {
    Object.assign(real, await createContext('security'));
    real.app = createApp({ pool: real.pool, config: real.config, log: (l) => logs.push(l) });
    strict = createApp({ pool: real.pool, config: testConfig(real.url, { AUTH_RATE_LIMIT_MAX: 3, RATE_LIMIT_MAX: 50 }), log: () => {} });
  }, 60_000);
  afterAll(() => real.close());

  it('helmet: header keamanan ada, x-powered-by tidak', async () => {
    const r = await request(real.app).get('/giveaways');
    expect(r.headers['x-content-type-options']).toBe('nosniff');
    expect(r.headers['x-powered-by']).toBeUndefined();
    expect(r.headers['strict-transport-security']).toBeDefined();
  });
  it('CORS: origin terdaftar diizinkan, lainnya tidak', async () => {
    const ok = await request(real.app).get('/giveaways').set('Origin', 'http://allowed.example');
    expect(ok.headers['access-control-allow-origin']).toBe('http://allowed.example');
    const bad = await request(real.app).get('/giveaways').set('Origin', 'http://evil.example');
    expect(bad.headers['access-control-allow-origin']).toBeUndefined();
    const pre = await request(real.app).options('/auth/login').set('Origin', 'http://evil.example').set('Access-Control-Request-Method', 'POST');
    expect(pre.headers['access-control-allow-origin']).toBeUndefined();
  });
  it('rate limit /auth/* lebih ketat -> 429', async () => {
    const codes = [];
    for (let i = 0; i < 5; i++) codes.push((await request(strict).post('/auth/salt').send({ identifier: 'x' })).status);
    expect(codes).toEqual([200, 200, 200, 429, 429]);
    const r = await request(strict).post('/auth/salt').send({});
    expect(r.body).toEqual({ ok: false, error: 'too_many_requests' });
    expect((await request(strict).get('/giveaways')).status).toBe(200); // endpoint lain memakai batas umum
  });
  it('JSON rusak -> 400, terlalu besar -> 413, rute tak dikenal -> 404 JSON', async () => {
    const bad = await request(real.app).post('/auth/login').set('Content-Type', 'application/json').send('{"identifier":');
    expect([bad.status, bad.body.error]).toEqual([400, 'invalid_json']);
    const big = await request(real.app).post('/auth/login').send({ identifier: 'x'.repeat(200_000) });
    expect(big.status).toBe(413);
    const nf = await request(real.app).get('/tidak-ada');
    expect([nf.status, nf.body]).toEqual([404, { ok: false, error: 'not_found' }]);
  });
  it('body bertipe salah tidak menjatuhkan server (bukan 500)', async () => {
    for (const body of [[], { identifier: { $ne: 1 }, password_hash: 5 }]) {
      const r = await request(real.app).post('/auth/login').set('Content-Type', 'application/json').send(JSON.stringify(body));
      expect(r.status).toBe(200);
      expect(r.body.error).toBe('invalid_credentials');
    }
    const reg = await request(real.app).post('/auth/register').set('Content-Type', 'application/json').send('[]');
    expect(reg.status).toBe(200);
    expect(reg.body.error).toBe('invalid_input');
    for (const raw of ['null', '"teks"']) {
      const r = await request(real.app).post('/auth/login').set('Content-Type', 'application/json').send(raw);
      expect([r.status, r.body.error]).toEqual([400, 'invalid_json']); // JSON ketat: hanya objek/array
    }
  });
  it('field role pada register diabaikan (tidak bisa jadi admin lewat API)', async () => {
    const r = await api.post('/auth/register', {
      body: { username: 'sneaky1', email: 's@example.com', full_name: 'S', salt: 'a'.repeat(32), password_hash: clientHash('x', 'a'.repeat(32)), role: 'admin' },
    });
    expect(r.ok).toBe(true);
    const { rows } = await real.su.query("select role from users where username='sneaky1'");
    expect(rows[0].role).toBe('user');
  });
  it('input berisi karakter SQL tersimpan/dicari sebagai teks (parameter, bukan string SQL)', async () => {
    const evil = "x'); drop table users; --";
    await register(api, 'inject1', 'inject@example.com', 'Passw0rd!1', evil);
    const tok = (await login(api, 'inject1', 'Passw0rd!1')).token;
    expect((await api.get('/auth/me', { token: tok })).user.full_name).toBe(evil);
    expect(await api.get('/giveaways', { query: { q: evil, category: evil, sort: evil } })).toEqual([]);
    expect(await api.get('/giveaways', { query: { q: evil, status: evil } })).toEqual({ ok: false, error: 'invalid_input', field: 'status' });
    expect((await real.su.query('select count(*)::int n from users')).rows[0].n).toBeGreaterThan(0);
  });
  it('log tidak memuat password hash, token, atau seed', async () => {
    const reg = await register(api, 'logger1', 'logger@example.com', 'Passw0rd!1', 'Logger');
    expect(reg.ok).toBe(true);
    const { salt } = await api.post('/auth/salt', { body: { identifier: 'logger1' } });
    const hash = clientHash('Passw0rd!1', salt);
    const lg = await api.post('/auth/login', { body: { identifier: 'logger1', password_hash: hash } });
    await api.get('/auth/me', { token: lg.token });
    await api.get('/giveaways', { query: { q: 'rahasia-pencarian' } });
    const all = logs.join('\n');
    expect(all).toContain('POST /auth/login 200');
    for (const secret of [hash, lg.token, 'rahasia-pencarian', 'Passw0rd!1']) expect(all).not.toContain(secret);
    expect(all).not.toMatch(/Bearer/i);
  });
  it('error internal -> 500 generik, pesan driver tidak bocor ke respons maupun log', async () => {
    const lines = [];
    const pool = { query: async () => { throw Object.assign(new Error('nilai-rahasia-dari-driver'), { code: 'XX000' }); } };
    const app = createApp({ pool, config: real.config, log: (l) => lines.push(l) });
    const r = await request(app).post('/auth/salt').send({ identifier: 'a' });
    expect([r.status, r.body]).toEqual([500, { ok: false, error: 'internal_error' }]);
    expect(JSON.stringify(r.body) + lines.join('\n')).not.toContain('nilai-rahasia-dari-driver');
  });
  it('token pengguna lain tidak memberi akses ke data pengguna lain', async () => {
    const t1 = (await login(api, 'logger1', 'Passw0rd!1')).token;
    const t2 = (await login(api, 'inject1', 'Passw0rd!1')).token;
    expect((await api.get('/auth/me', { token: t1 })).user.username).toBe('logger1');
    expect((await api.get('/auth/me', { token: t2 })).user.username).toBe('inject1');
    expect(await api.get('/tickets', { token: t1 })).toEqual([]);
  });
});

describe('konfigurasi', () => {
  it('DATABASE_URL wajib; pesan galat tidak mengulang nilai env', () => {
    expect(() => loadConfig({})).toThrow(/DATABASE_URL/);
    expect(() => loadConfig({ DATABASE_URL: 'postgres://u:rahasiaPW@h/db', TICK_SECRET: 'pendek' })).toThrow(/TICK_SECRET/);
    try {
      loadConfig({ DATABASE_URL: 'postgres://u:rahasiaPW@h/db', PORT: 'abc' });
    } catch (e) {
      expect(e.message).not.toContain('rahasiaPW');
    }
  });
  it('nilai bawaan dan CORS_ORIGINS terurai', () => {
    const c = loadConfig({ DATABASE_URL: 'x', CORS_ORIGINS: 'http://a.test, http://b.test ' });
    expect(c.PORT).toBe(3000);
    expect(c.corsOrigins).toEqual(['http://a.test', 'http://b.test']);
    expect(c.SCHEDULER_ENABLED).toBe(true);
  });
});
