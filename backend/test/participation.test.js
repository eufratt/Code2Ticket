import fs from 'node:fs';
import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import {
  BACKEND_SQL, PARTICIPATION_SQL, PHOTOS_SQL, PRIZE_IDR_SQL, createContext, createTestDb, giveawayBody, login, makeApi, register,
} from './helpers.js';
import { isHttpsUrl } from '../src/services/admin.js';

// Cara mendapatkan kode + tautan penyelenggara (migrasi 09, validasi admin, respons).
const real = {};
const api = makeApi(() => real.app);
let adm;
const post = (body) => api.post('/admin/giveaways', { token: adm, body: giveawayBody({ title: 'Info ikut', ...body }) });
const HOWTO = 'Ikuti penyelenggara untuk kodenya.';

beforeAll(async () => {
  Object.assign(real, await createContext('participation'));
  await register(api, 'admin04', 'admin4@example.com', 'Adm1nPass!', 'Admin');
  await real.su.query("update users set role='admin'");
  adm = (await login(api, 'admin04', 'Adm1nPass!')).token;
}, 60_000);
afterAll(() => real.close());

describe('validasi admin', () => {
  it('https diterima, di-trim, round-trip di detail; daftar membawa organizer_url tanpa how_to_participate', async () => {
    const r = await post({ how_to_participate: '  Cari kode di Instagram penyelenggara.\nBaris kedua.  ', organizer_url: '  https://example.com/giveaway?a=1  ' });
    expect(r.ok).toBe(true);
    const one = await api.get(`/giveaways/${r.giveaway_id}`);
    expect(one.how_to_participate).toBe('Cari kode di Instagram penyelenggara.\nBaris kedua.');
    expect(one.organizer_url).toBe('https://example.com/giveaway?a=1');
    const list = (await api.get('/giveaways', { query: { q: 'Info ikut' } })).find((g) => g.id === r.giveaway_id);
    expect(list.organizer_url).toBe(one.organizer_url);
    expect(list).not.toHaveProperty('how_to_participate');
  });

  it('organizer_url kosong / null / absen diterima (NULL)', async () => {
    for (const v of [undefined, '', null]) {
      const r = await post({ how_to_participate: HOWTO, organizer_url: v });
      expect(r.ok, String(v)).toBe(true);
      expect((await api.get(`/giveaways/${r.giveaway_id}`)).organizer_url).toBeNull();
    }
  });

  it.each([
    ['http', 'http://example.com'], ['javascript:', 'javascript:alert(1)'], ['data:', 'data:text/html;base64,AAAA'], ['file:', 'file:///etc/passwd'],
    ['ftp', 'ftp://example.com'], ['kredensial', 'https://user:pass@example.com'], ['spasi', 'https://exa mple.com'],
    ['karakter kontrol', 'https://example.com/\u0001'], ['tanpa skema', 'example.com'], ['host tanpa titik', 'https://localhost'],
    ['IP', 'https://127.0.0.1/'], ['terlalu panjang', `https://example.com/${'a'.repeat(500)}`], ['bukan teks', 123],
  ])('organizer_url tidak valid (%s) -> invalid_input field organizer_url', async (_n, v) => {
    const r = await post({ how_to_participate: HOWTO, organizer_url: v });
    expect(r).toMatchObject({ ok: false, error: 'invalid_input', field: 'organizer_url' });
  });

  it.each([
    ['hilang', undefined], ['kosong', ''], ['spasi saja', '          '], ['9 karakter', '123456789'], ['terlalu panjang', 'x'.repeat(2001)], ['bukan teks', 5],
  ])('how_to_participate wajib 10..2000 setelah trim (%s)', async (_n, v) => {
    const r = await post({ how_to_participate: v });
    expect(r).toMatchObject({ ok: false, error: 'invalid_input', field: 'how_to_participate' });
  });

  it('batas: 10 dan 2000 karakter diterima', async () => {
    expect((await post({ how_to_participate: '1234567890' })).ok).toBe(true);
    expect((await post({ how_to_participate: 'x'.repeat(2000) })).ok).toBe(true);
  });

  it('isHttpsUrl: contoh sah', () => {
    for (const u of ['https://example.com', 'https://sub.example.co.id/path?q=1#x', 'HTTPS://Example.com']) expect(isHttpsUrl(u), u).toBe(true);
  });

  it('ubah: isi baru tersimpan, absen = tetap, organizer_url dikosongkan dengan null, tidak valid ditolak', async () => {
    const id = (await post({ how_to_participate: 'Cara awal mendapatkan kode.', organizer_url: 'https://example.com/a' })).giveaway_id;
    const upd = (body) => api.post('/admin/giveaways', { token: adm, body: { id, ...body } });
    expect((await upd({ title: 'Judul baru' })).ok).toBe(true);
    let g = await api.get(`/giveaways/${id}`);
    expect([g.how_to_participate, g.organizer_url]).toEqual(['Cara awal mendapatkan kode.', 'https://example.com/a']);
    expect((await upd({ how_to_participate: 'Cara baru mendapatkan kode.', organizer_url: null })).ok).toBe(true);
    g = await api.get(`/giveaways/${id}`);
    expect([g.how_to_participate, g.organizer_url]).toEqual(['Cara baru mendapatkan kode.', null]);
    expect(await upd({ organizer_url: 'http://example.com' })).toMatchObject({ ok: false, field: 'organizer_url' });
    expect(await upd({ how_to_participate: 'pendek' })).toMatchObject({ ok: false, field: 'how_to_participate' });
  });
});

describe('migrasi 09', () => {
  it('idempotent, data lama NULL, CHECK panjang', async () => {
    const url = await createTestDb('participation_mig', [BACKEND_SQL, PHOTOS_SQL, PRIZE_IDR_SQL]);
    const c = new pg.Client({ connectionString: url });
    await c.connect();
    try {
      await c.query(
        `insert into giveaways(title, category, prize_name, prize_value_idr, start_at, end_at, draw_at, winner_count, seed_hash)
         values ('lama','tech','X',1, now(), now()+interval '1 hour', now()+interval '2 hours', 1, repeat('a',64))`,
      );
      const sql = fs.readFileSync(PARTICIPATION_SQL, 'utf8');
      await c.query(sql);
      await c.query(sql);
      const row = (await c.query('select how_to_participate, organizer_url from giveaways')).rows[0];
      expect(row).toEqual({ how_to_participate: null, organizer_url: null });
      await expect(c.query("update giveaways set how_to_participate = repeat('x', 2001)")).rejects.toThrow(/giveaways_how_to_participate_len/);
      await expect(c.query("update giveaways set organizer_url = 'https://e.com/' || repeat('x', 500)")).rejects.toThrow(/giveaways_organizer_url_len/);
    } finally {
      await c.end();
    }
  }, 60_000);
});
