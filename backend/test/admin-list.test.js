import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createContext, HOUR, login, makeApi, mkGiveaway, register } from './helpers.js';

describe('GET /admin/giveaways', () => {
  const real = {};
  const api = makeApi(() => real.app);
  const ids = {};
  let adm;
  let user;

  beforeAll(async () => {
    Object.assign(real, await createContext('adminlist'));
    await register(api, 'admin01', 'admin@example.com', 'Adm1nPass!', 'Admin');
    await register(api, 'user01', 'user@example.com', 'Us3rPass!', 'User');
    await real.su.query("update users set role='admin' where username='admin01'");
    adm = (await login(api, 'admin01', 'Adm1nPass!')).token;
    user = (await login(api, 'user01', 'Us3rPass!')).token;
    ids.active = (await mkGiveaway(api, adm, { title: 'Aktif' })).giveaway_id;
    ids.upcoming = (await mkGiveaway(api, adm, { title: 'Segera', start: 2 * HOUR, end: 3 * HOUR, draw: 4 * HOUR })).giveaway_id;
    ids.waiting = (await mkGiveaway(api, adm, { title: 'Menunggu', start: -3 * HOUR, end: HOUR, draw: 2 * HOUR })).giveaway_id;
    await real.su.query("update giveaways set end_at = now() - interval '1 minute' where id = $1", [ids.waiting]);
    ids.drawn = (await mkGiveaway(api, adm, { title: 'Selesai' })).giveaway_id;
    await real.su.query("update giveaways set status = 'drawn' where id = $1", [ids.drawn]);
  }, 60_000);
  afterAll(() => real.close());

  it('admin melihat semua status', async () => {
    const list = await api.get('/admin/giveaways', { token: adm });
    const status = Object.fromEntries(list.map((g) => [g.id, g.status]));
    expect(status).toEqual({
      [ids.active]: 'active', [ids.upcoming]: 'upcoming', [ids.waiting]: 'waiting_draw', [ids.drawn]: 'drawn',
    });
  });

  it('GET /giveaways publik tetap hanya yang aktif', async () => {
    const list = await api.get('/giveaways');
    expect(list.map((g) => g.id)).toEqual([ids.active]);
  });

  it('non-admin 403, tanpa sesi 401', async () => {
    const r = await api.raw('get', '/admin/giveaways', { token: user });
    expect(r.status).toBe(403);
    expect(r.body).toEqual({ ok: false, error: 'forbidden' });
    expect((await api.raw('get', '/admin/giveaways')).status).toBe(401);
  });

  it('paginasi dengan limit dan offset', async () => {
    const first = await api.get('/admin/giveaways?limit=2', { token: adm });
    const rest = await api.get('/admin/giveaways?limit=2&offset=2', { token: adm });
    expect(first).toHaveLength(2);
    expect(new Set([...first, ...rest].map((g) => g.id)).size).toBe(4);
  });
});
