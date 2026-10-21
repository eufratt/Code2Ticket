import fs from 'node:fs';
import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import {
  BACKEND_SQL, PHOTOS_SQL, PRIZE_IDR_SQL, createContext, createTestDb, giveawayBody, login, makeApi, mkGiveaway, register,
} from './helpers.js';

// Nilai hadiah berbasis rupiah (migrasi 08, admin create/update, filter dan sort pada IDR).
const real = {};
const api = makeApi(() => real.app);
let adm;

beforeAll(async () => {
  Object.assign(real, await createContext('prizeidr'));
  await register(api, 'admin03', 'admin3@example.com', 'Adm1nPass!', 'Admin');
  await real.su.query("update users set role='admin'");
  adm = (await login(api, 'admin03', 'Adm1nPass!')).token;
}, 60_000);
afterAll(() => real.close());

describe('admin create: nilai hadiah rupiah', () => {
  it('round-trip: Rp 5.000.000 tersimpan dan terbaca persis sama (daftar, detail, kolom)', async () => {
    const c = await mkGiveaway(api, adm, { title: 'Roundtrip', prize_value_idr: 5_000_000 });
    expect(c.ok).toBe(true);
    const one = await api.get(`/giveaways/${c.giveaway_id}`);
    expect(one.prize_value_idr).toBe(5_000_000);
    expect(one).not.toHaveProperty('prize_value_usd');
    const list = await api.get('/giveaways', { query: { q: 'Roundtrip' } });
    expect(list.map((g) => g.prize_value_idr)).toEqual([5_000_000]);
    const row = (await real.su.query('select prize_value_idr::text as v from giveaways where id = $1', [c.giveaway_id])).rows[0];
    expect(row.v).toBe('5000000');
  });

  it('batas atas Rp 100.000.000.000 diterima', async () => {
    const r = await mkGiveaway(api, adm, { title: 'Maks', prize_value_idr: 100_000_000_000 });
    expect(r.ok).toBe(true);
  });

  it.each([
    ['nol', 0], ['negatif', -1], ['desimal', 1500.5], ['di atas batas', 100_000_000_001], ['teks', '5000000'], ['null', null], ['NaN', 'abc'],
  ])('nilai tidak valid (%s) -> invalid_input field prize_value_idr', async (_n, v) => {
    const r = await api.post('/admin/giveaways', { token: adm, body: giveawayBody({ title: 'Salah', prize_value_idr: v }) });
    expect(r).toMatchObject({ ok: false, error: 'invalid_input', field: 'prize_value_idr' });
  });

  it('field lama prize_value_usd saja (tanpa prize_value_idr) ditolak', async () => {
    const { prize_value_idr: _drop, ...rest } = giveawayBody({ title: 'Lama' });
    const r = await api.post('/admin/giveaways', { token: adm, body: { ...rest, prize_value_usd: 500 } });
    expect(r).toMatchObject({ ok: false, error: 'invalid_input', field: 'prize_value_idr' });
  });

  it('ubah nilai hadiah: valid tersimpan, tidak valid ditolak, absen = dipertahankan', async () => {
    const id = (await mkGiveaway(api, adm, { title: 'Ubah', start: 3_600_000, end: 7_200_000, draw: 10_800_000 })).giveaway_id;
    const upd = (body) => api.post('/admin/giveaways', { token: adm, body: { id, ...body } });
    expect((await upd({ prize_value_idr: 7_500_000 })).ok).toBe(true);
    expect((await api.get(`/giveaways/${id}`)).prize_value_idr).toBe(7_500_000);
    expect(await upd({ prize_value_idr: 0.5 })).toMatchObject({ ok: false, error: 'invalid_input', field: 'prize_value_idr' });
    expect((await upd({ title: 'Ubah 2' })).ok).toBe(true);
    expect((await api.get(`/giveaways/${id}`)).prize_value_idr).toBe(7_500_000);
  });
});

describe('filter dan sort pada rupiah', () => {
  it('min_value / max_value (rupiah) inklusif dan sort=value menurun', async () => {
    const mk = (title, v) => mkGiveaway(api, adm, { title, prize_value_idr: v });
    await mk('Fl Murah', 1_000_000);
    await mk('Fl Sedang', 2_500_000);
    await mk('Fl Mahal', 90_000_000);
    const t = async (query) => (await api.get('/giveaways', { query: { q: 'Fl', ...query } })).map((g) => g.title);
    expect(await t({ min_value: 2_500_000 })).toEqual(expect.arrayContaining(['Fl Sedang', 'Fl Mahal']));
    expect(await t({ min_value: 2_500_001 })).toEqual(['Fl Mahal']);
    expect(await t({ max_value: 2_500_000 })).toEqual(expect.arrayContaining(['Fl Murah', 'Fl Sedang']));
    expect(await t({ max_value: 2_500_000 })).not.toContain('Fl Mahal');
    expect(await t({ min_value: 1_000_000, max_value: 2_500_000, sort: 'value' })).toEqual(['Fl Sedang', 'Fl Murah']);
    expect(await t({ sort: 'value' })).toEqual(['Fl Mahal', 'Fl Sedang', 'Fl Murah']);
  });
});

describe('migrasi 08_prize_value_idr.sql', () => {
  it('backfill kurs 18.000 dibulatkan ribuan, dibatasi, tidak menimpa nilai IDR, idempotent, insert tanpa kolom lama lolos', async () => {
    const url = await createTestDb('prizeidr_mig', [BACKEND_SQL, PHOTOS_SQL]); // sebelum 08
    const c = new pg.Client({ connectionString: url });
    await c.connect();
    try {
      const ins = (title, usd) =>
        c.query(
          `insert into giveaways(title, category, prize_name, prize_value_usd, start_at, end_at, draw_at, winner_count, seed_hash)
           values ($1,'tech','X',$2, now(), now()+interval '1 hour', now()+interval '2 hours', 1, repeat('a',64))`,
          [title, usd],
        );
      await ins('a', 1200); await ins('b', 35.5); await ins('c', 0.01); await ins('d', 0); await ins('e', 9999999999.99);
      const sql = fs.readFileSync(PRIZE_IDR_SQL, 'utf8');
      await c.query(sql);
      const get = async () => Object.fromEntries((await c.query('select title, prize_value_idr::text v from giveaways')).rows.map((r) => [r.title, r.v]));
      expect(await get()).toEqual({ a: '21600000', b: '639000', c: '0', d: '0', e: '100000000000' });

      await c.query("update giveaways set prize_value_idr = 5000000 where title = 'a'"); // admin mengisi sendiri
      await c.query(sql); // jalankan ulang
      expect((await get()).a).toBe('5000000');
      expect((await get()).b).toBe('639000');

      // kode baru tidak mengisi prize_value_usd: tidak boleh gagal NOT NULL
      await c.query(
        `insert into giveaways(title, category, prize_name, prize_value_idr, start_at, end_at, draw_at, winner_count, seed_hash)
         values ('f','tech','X',1, now(), now()+interval '1 hour', now()+interval '2 hours', 1, repeat('a',64))`,
      );
      await expect(c.query("update giveaways set prize_value_idr = -1 where title = 'f'")).rejects.toThrow(/giveaways_prize_value_idr_range/);
      await expect(c.query("update giveaways set prize_value_idr = 100000000001 where title = 'f'")).rejects.toThrow();
    } finally {
      await c.end();
    }
  }, 60_000);
});
