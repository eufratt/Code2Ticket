import fs from 'node:fs';
import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import {
  BACKEND_SQL, PARTICIPATION_SQL, PHOTOS_SQL, PRIZE_IDR_SQL, REDEEM_GEO_SQL, createContext, createTestDb, genCodes,
  login, makeApi, mkGiveaway, redeem, register,
} from './helpers.js';

describe('batas lokasi tukar kode per giveaway', () => {
  const real = {};
  const api = makeApi(() => real.app);
  const ids = {};
  let adm;
  let bob;
  const near = [-6.205, 106.82];
  const far = [-6.9175, 107.6191]; // Bandung

  beforeAll(async () => {
    Object.assign(real, await createContext('redeemgeo'));
    await register(api, 'admin01', 'admin@example.com', 'Adm1nPass!', 'Admin');
    await register(api, 'bob01', 'bob@example.com', 'B0bPass!!', 'Bob');
    await real.su.query("update users set role='admin' where username='admin01'");
    adm = (await login(api, 'admin01', 'Adm1nPass!')).token;
    bob = (await login(api, 'bob01', 'B0bPass!!')).token;
    ids.geo = (await mkGiveaway(api, adm, { title: 'Terbatas', lat: -6.2, lng: 106.8, radius_km: 5, redeem_geo_restricted: true, maxTickets: 50 })).giveaway_id;
    ids.free = (await mkGiveaway(api, adm, { title: 'Bebas', lat: -6.2, lng: 106.8, radius_km: 5, maxTickets: 50 })).giveaway_id;
  }, 60_000);
  afterAll(() => real.close());

  it('terbatas: tanpa lokasi location_required, luar radius out_of_area, dalam radius sukses', async () => {
    const [a] = await genCodes(api, adm, ids.geo, 1);
    expect((await redeem(api, bob, a)).error).toBe('location_required');
    expect((await redeem(api, bob, a, ...far)).error).toBe('out_of_area');
    expect((await redeem(api, bob, a, ...near)).ok).toBe(true);
  });

  it('tidak terbatas: tanpa lokasi atau jauh tetap sukses', async () => {
    const [a, b] = await genCodes(api, adm, ids.free, 2);
    expect((await redeem(api, bob, a)).ok).toBe(true);
    expect((await redeem(api, bob, b, ...far)).ok).toBe(true);
  });

  it('geo_* lama di baris codes diabaikan', async () => {
    const [a] = await genCodes(api, adm, ids.free, 1);
    await real.su.query('update codes set geo_lat=-6.2, geo_lng=106.8, geo_radius_km=1 where code=$1', [a]);
    expect((await redeem(api, bob, a, ...far)).ok).toBe(true);
    const [b] = await genCodes(api, adm, ids.geo, 1);
    expect((await redeem(api, bob, b, ...far)).error).toBe('out_of_area'); // kode tanpa geo_* tetap dibatasi giveaway
  });

  it('koordinat request tidak valid ditolak', async () => {
    const [a] = await genCodes(api, adm, ids.geo, 1);
    expect((await redeem(api, bob, a, 91, 106.8)).error).toBe('invalid_input');
    expect((await redeem(api, bob, a, 'x', 106.8)).error).toBe('invalid_input');
  });

  it('list dan detail menyertakan redeem_geo_restricted', async () => {
    const list = await api.get('/giveaways');
    expect(list.find((g) => g.id === ids.geo).redeem_geo_restricted).toBe(true);
    expect(list.find((g) => g.id === ids.free).redeem_geo_restricted).toBe(false);
    expect((await api.get(`/giveaways/${ids.geo}`)).redeem_geo_restricted).toBe(true);
  });

  it('admin: saklar tanpa koordinat atau radius -> invalid_input field redeem_geo_restricted', async () => {
    for (const extra of [{ lat: null, lng: null, radius_km: 5 }, { radius_km: null }, { radius_km: 0 }]) {
      const r = await mkGiveaway(api, adm, { title: 'X', redeem_geo_restricted: true, ...extra });
      expect(r).toMatchObject({ ok: false, error: 'invalid_input', field: 'redeem_geo_restricted' });
    }
    expect((await mkGiveaway(api, adm, { title: 'X', redeem_geo_restricted: 'ya' })).error).toBe('invalid_input');
  });

  it('admin: ubah saklar hanya sebelum ada tiket (redeem_geo_locked)', async () => {
    const fresh = (await mkGiveaway(api, adm, { title: 'Ubah', lat: -6.2, lng: 106.8, radius_km: 5 })).giveaway_id;
    expect((await api.post('/admin/giveaways', { token: adm, body: { id: fresh, redeem_geo_restricted: true } })).ok).toBe(true);
    const bad = await api.post('/admin/giveaways', { token: adm, body: { id: fresh, radius_km: null } });
    expect(bad).toMatchObject({ error: 'invalid_input', field: 'redeem_geo_restricted' });
    const [code] = await genCodes(api, adm, fresh, 1);
    expect((await redeem(api, bob, code, ...near)).ok).toBe(true);
    const locked = await api.post('/admin/giveaways', { token: adm, body: { id: fresh, redeem_geo_restricted: false } });
    expect(locked).toMatchObject({ ok: false, error: 'redeem_geo_locked' });
    expect((await api.post('/admin/giveaways', { token: adm, body: { id: fresh, radius_km: 50 } })).error).toBe('redeem_geo_locked');
    expect((await api.post('/admin/giveaways', { token: adm, body: { id: fresh, title: 'Ubah 2' } })).ok).toBe(true);
  });

  it('generate kode menolak geo_* per kode', async () => {
    const r = await api.post(`/admin/giveaways/${ids.free}/codes`, { token: adm, body: { count: 1, geo_lat: 1, geo_lng: 1, geo_radius_km: 1 } });
    expect(r).toMatchObject({ ok: false, error: 'invalid_input', field: 'geo' });
  });

  it('migrasi 10: idempotent, default false, CHECK menolak terbatas tanpa lokasi', async () => {
    const url = await createTestDb('redeemgeomig', [BACKEND_SQL, PHOTOS_SQL, PRIZE_IDR_SQL, PARTICIPATION_SQL]);
    const c = new pg.Client({ connectionString: url });
    await c.connect();
    try {
      const sql = fs.readFileSync(REDEEM_GEO_SQL, 'utf8');
      await c.query(sql);
      await c.query(sql);
      const col = (await c.query("select column_default, is_nullable from information_schema.columns where table_name='giveaways' and column_name='redeem_geo_restricted'")).rows[0];
      expect(col).toEqual({ column_default: 'false', is_nullable: 'NO' });
      await expect(c.query(
        `insert into giveaways(title, category, prize_name, prize_value_idr, start_at, end_at, draw_at, winner_count, seed_hash, redeem_geo_restricted)
         values ('x','tech','x',1000,now(),now()+interval '1 hour',now()+interval '2 hours',1,repeat('a',64),true)`,
      )).rejects.toMatchObject({ code: '23514' });
    } finally {
      await c.end();
    }
  });
});
