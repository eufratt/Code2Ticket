import crypto from 'node:crypto';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { createContext, login, makeApi, register, testConfig } from './helpers.js';

// JPEG "cukup valid" untuk pemeriksaan penanda: SOI + isi acak + EOI.
const jpeg = (n = 2000) => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), crypto.randomBytes(n), Buffer.from([0xff, 0xd9])]);

describe('foto profil: PUT /me/photo dan GET /users/:id/photo', () => {
  const real = {};
  const api = makeApi(() => real.app);
  let tok, tok2, uid, uid2;
  const put = (t, body, type = 'image/jpeg') => {
    let r = request(real.app).put('/me/photo').set('Content-Type', type);
    if (t) r = r.set('Authorization', `Bearer ${t}`);
    return r.send(body);
  };

  beforeAll(async () => {
    Object.assign(real, await createContext('photo'));
    await register(api, 'fotouser', 'foto@example.com', 'Passw0rd!1', 'Foto User');
    await register(api, 'fotouser2', 'foto2@example.com', 'Passw0rd!1', 'Foto Dua');
    const l1 = await login(api, 'fotouser', 'Passw0rd!1');
    const l2 = await login(api, 'fotouser2', 'Passw0rd!1');
    [tok, uid, tok2, uid2] = [l1.token, l1.user.id, l2.token, l2.user.id];
  }, 60_000);
  afterAll(() => real.close());

  it('tanpa token -> 401; foto tidak tersimpan', async () => {
    const r = await put(null, jpeg());
    expect([r.status, r.body.error]).toEqual([401, 'invalid_session']);
    expect((await real.su.query('select count(*)::int n from user_photos')).rows[0].n).toBe(0);
  });

  it('sebelum ada foto: GET -> 404 not_found', async () => {
    const r = await request(real.app).get(`/users/${uid}/photo`);
    expect([r.status, r.body]).toEqual([404, { ok: false, error: 'not_found' }]);
  });

  let first;
  it('unggah JPEG: ok, photo_url relatif dengan versi, tampil di /auth/me', async () => {
    first = jpeg();
    const r = await put(tok, first);
    expect(r.status).toBe(200);
    expect(r.body.ok).toBe(true);
    expect(r.body.user.photo_url).toMatch(new RegExp(`^/users/${uid}/photo\\?v=\\d+$`));
    expect((await api.get('/auth/me', { token: tok })).user.photo_url).toBe(r.body.user.photo_url);
  });

  it('GET publik (tanpa token): bytes sama, Content-Type, Cache-Control, ETag', async () => {
    const r = await request(real.app).get(`/users/${uid}/photo`).buffer(true).parse((res, cb) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => cb(null, Buffer.concat(chunks)));
    });
    expect(r.status).toBe(200);
    expect(r.headers['content-type']).toBe('image/jpeg');
    expect(r.headers['cache-control']).toMatch(/max-age=\d+/);
    expect(r.headers.etag).toMatch(/^"\d+"$/);
    expect(r.headers['cross-origin-resource-policy']).toBe('cross-origin');
    expect(Buffer.compare(r.body, first)).toBe(0);
  });

  it('If-None-Match yang cocok -> 304 tanpa isi', async () => {
    const etag = (await request(real.app).get(`/users/${uid}/photo`)).headers.etag;
    const r = await request(real.app).get(`/users/${uid}/photo`).set('If-None-Match', etag);
    expect(r.status).toBe(304);
  });

  it('ganti foto: bytes baru, versi (?v=) dan ETag berubah, tetap satu baris', async () => {
    const before = (await api.get('/auth/me', { token: tok })).user.photo_url;
    await new Promise((r) => setTimeout(r, 5));
    const second = jpeg(3000);
    const r = await put(tok, second);
    expect(r.body.user.photo_url).not.toBe(before);
    const g = await request(real.app).get(`/users/${uid}/photo`).buffer(true).parse((res, cb) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => cb(null, Buffer.concat(chunks)));
    });
    expect(Buffer.compare(g.body, second)).toBe(0);
    expect((await real.su.query('select count(*)::int n from user_photos where user_id=$1', [uid])).rows[0].n).toBe(1);
  });

  it('terlalu besar (>150 KB) -> 413 dan foto lama tetap', async () => {
    const r = await put(tok, jpeg(150 * 1024));
    expect([r.status, r.body.error]).toEqual([413, 'payload_too_large']);
    const ok = await put(tok, jpeg(150 * 1024 - 100)); // tepat di bawah batas diterima
    expect(ok.status).toBe(200);
  });

  it('bukan JPEG (PNG / teks) dengan Content-Type image/jpeg -> invalid_input', async () => {
    const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), crypto.randomBytes(200)]);
    for (const body of [png, Buffer.from('ini bukan gambar sama sekali')]) {
      const r = await put(tok, body);
      expect([r.status, r.body.error, r.body.field]).toEqual([200, 'invalid_input', 'photo']);
    }
  });

  it('JPEG terpotong (tanpa penanda akhir) ditolak', async () => {
    const r = await put(tok, Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), crypto.randomBytes(500)]));
    expect(r.body.error).toBe('invalid_input');
  });

  it('Content-Type lain (image/png, json) ditolak; badan kosong ditolak', async () => {
    expect((await put(tok, jpeg(), 'image/png')).body).toMatchObject({ ok: false, error: 'invalid_input', field: 'content_type' });
    expect((await put(tok, Buffer.alloc(0))).body).toMatchObject({ ok: false, error: 'invalid_input' });
    const j = await request(real.app).put('/me/photo').set('Authorization', `Bearer ${tok}`).send({ a: 1 });
    expect(j.body.error).toBe('invalid_input');
  });

  it('foto pengguna lain tidak tertimpa; masing-masing punya fotonya', async () => {
    const mine2 = jpeg(1234);
    await put(tok2, mine2);
    const g = await request(real.app).get(`/users/${uid2}/photo`).buffer(true).parse((res, cb) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => cb(null, Buffer.concat(chunks)));
    });
    expect(Buffer.compare(g.body, mine2)).toBe(0);
    expect((await real.su.query('select count(*)::int n from user_photos')).rows[0].n).toBe(2);
  });

  it('id tidak ada / bukan UUID -> 404', async () => {
    for (const id of ['00000000-0000-4000-8000-000000000000', 'bukan-uuid']) {
      expect((await request(real.app).get(`/users/${id}/photo`)).status).toBe(404);
    }
  });

  it('tabel user_photos tertutup untuk role anon', async () => {
    await real.anon.query('select 1').catch(() => {});
    let code;
    try {
      await real.anon.query('select * from public.user_photos limit 1');
    } catch (e) {
      code = e.code;
    }
    expect(code).toBe('42501');
  });

  it('rate limit unggah -> 429 setelah batas', async () => {
    const strict = createApp({ pool: real.pool, config: testConfig(real.url, { UPLOAD_RATE_LIMIT_MAX: 2 }), log: () => {} });
    const codes = [];
    for (let i = 0; i < 4; i++) {
      codes.push((await request(strict).put('/me/photo').set('Authorization', `Bearer ${tok}`).set('Content-Type', 'image/jpeg').send(jpeg(300))).status);
    }
    expect(codes).toEqual([200, 200, 429, 429]);
  });

  it('PATCH /me tetap bisa dipakai bersama foto (nama berubah, foto tetap)', async () => {
    const before = (await api.get('/auth/me', { token: tok })).user.photo_url;
    const r = await api.patch('/me', { token: tok, body: { full_name: 'Nama Baru' } });
    expect(r.user.full_name).toBe('Nama Baru');
    expect(r.user.photo_url).toBe(before);
  });
});
