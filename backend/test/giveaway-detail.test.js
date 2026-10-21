import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createContext, login, makeApi, mkGiveaway, register } from './helpers.js';

describe('GET /giveaways/:id dan pengurutan daftar', () => {
  const real = {};
  const api = makeApi(() => real.app);
  let adm;
  const ids = {};

  beforeAll(async () => {
    Object.assign(real, await createContext('detail'));
    await register(api, 'admin01', 'admin@example.com', 'Adm1nPass!', 'Admin');
    await real.su.query("update users set role='admin'");
    adm = (await login(api, 'admin01', 'Adm1nPass!')).token;
    const H = 3_600_000;
    ids.mid = (await mkGiveaway(api, adm, { title: 'Mid', end: 5 * H, draw: 6 * H, lat: -6.2, lng: 106.8 })).giveaway_id;
    ids.soon = (await mkGiveaway(api, adm, { title: 'Soon', end: 1 * H, draw: 2 * H, lat: -6.9, lng: 107.6 })).giveaway_id;
    ids.late = (await mkGiveaway(api, adm, { title: 'Late', end: 9 * H, draw: 10 * H, lat: null, lng: null })).giveaway_id;
    await real.su.query('update giveaways set prize_value_idr = 500000 where id = $1', [ids.soon]);
    await real.su.query('update giveaways set prize_value_idr = 9000000 where id = $1', [ids.late]);
  }, 60_000);
  afterAll(() => real.close());

  it('bentuk sama dengan item daftar (distance_km null)', async () => {
    const list = await api.get('/giveaways');
    const one = await api.get(`/giveaways/${ids.mid}`);
    expect(one).toEqual({ ...list.find((g) => g.id === ids.mid), distance_km: null });
    expect(Object.keys(one).sort()).toEqual(Object.keys(list[0]).sort());
  });

  it('publik: tanpa token; giveaway yang sudah di-draw tetap bisa dibaca', async () => {
    await real.su.query("update giveaways set status = 'drawn' where id = $1", [ids.late]);
    const r = await api.raw('get', `/giveaways/${ids.late}`);
    expect(r.status).toBe(200);
    expect(r.body.status).toBe('drawn');
    await real.su.query("update giveaways set status = 'active' where id = $1", [ids.late]);
  });

  it('ticket_count mengikuti ticket_counter', async () => {
    await real.su.query('update giveaways set ticket_counter = 7 where id = $1', [ids.mid]);
    expect((await api.get(`/giveaways/${ids.mid}`)).ticket_count).toBe(7);
  });

  it('tidak ada -> 404 {ok:false,error:not_found}; bukan UUID juga 404', async () => {
    for (const id of ['00000000-0000-4000-8000-000000000000', 'bukan-uuid', '123']) {
      const r = await api.raw('get', `/giveaways/${id}`);
      expect([r.status, r.body]).toEqual([404, { ok: false, error: 'not_found' }]);
    }
  });

  it('rute /:id tidak menutupi /:id/winners dan /:id/verification', async () => {
    expect((await api.get(`/giveaways/${ids.mid}/winners`)).drawn).toBe(false);
    expect((await api.get(`/giveaways/${ids.mid}/verification`)).giveaway.id).toBe(ids.mid);
  });

  it('urutan: deadline (bawaan), nilai hadiah, terdekat, terbaru', async () => {
    const titles = async (query) => (await api.get('/giveaways', { query })).map((g) => g.title);
    expect(await titles({})).toEqual(['Soon', 'Mid', 'Late']);
    expect(await titles({ sort: 'value' })).toEqual(['Late', 'Mid', 'Soon']);
    expect(await titles({ sort: 'nearest', lat: -6.2, lng: 106.8 })).toEqual(['Mid', 'Soon', 'Late']);
  });

  it('nearby: radius membatasi hasil dan distance_km terisi', async () => {
    const r = await api.get('/giveaways', { query: { lat: -6.2, lng: 106.8, radius_km: 25 } });
    expect(r.map((g) => g.title)).toEqual(['Mid']);
    expect(r[0].distance_km).toBe(0);
    const wide = await api.get('/giveaways', { query: { lat: -6.2, lng: 106.8, radius_km: 200, sort: 'nearest' } });
    expect(wide.map((g) => g.title)).toEqual(['Mid', 'Soon']);
    expect(wide[1].distance_km).toBeGreaterThan(100);
  });

  it('rentang nilai hadiah dan kategori digabung dengan kata kunci', async () => {
    const t = async (query) => (await api.get('/giveaways', { query })).map((g) => g.title);
    expect(await t({ min_value: 1000000, max_value: 6000000 })).toEqual(['Mid']);
    expect(await t({ q: 'soo', category: 'tech' })).toEqual(['Soon']);
    expect(await t({ q: 'soo', category: 'food' })).toEqual([]);
  });
});
