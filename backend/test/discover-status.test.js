import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createContext, HOUR, login, makeApi, mkGiveaway, register } from './helpers.js';

// Cakupan status GET /giveaways (Discover): bawaan aktif + akan datang, kata kunci = semua status, status eksplisit dipatuhi.
describe('GET /giveaways: cakupan status', () => {
  const real = {};
  const api = makeApi(() => real.app);
  const ids = {};
  const titles = (list) => list.map((g) => g.title);

  beforeAll(async () => {
    Object.assign(real, await createContext('discoverstatus'));
    await register(api, 'admin03', 'admin3@example.com', 'Adm1nPass!', 'Admin');
    await real.su.query("update users set role='admin'");
    const adm = (await login(api, 'admin03', 'Adm1nPass!')).token;
    const mk = async (key, opts) => { ids[key] = (await mkGiveaway(api, adm, { title: `Kamera ${key}`, ...opts })).giveaway_id; };
    await mk('aktif-lama', { end: 5 * HOUR, draw: 6 * HOUR, prize_value_idr: 1_000_000 });
    await mk('aktif-dekat', { end: 2 * HOUR, draw: 3 * HOUR, prize_value_idr: 9_000_000 });
    await mk('segera-jauh', { start: 5 * HOUR, end: 6 * HOUR, draw: 7 * HOUR });
    await mk('segera-dekat', { start: 2 * HOUR, end: 6 * HOUR, draw: 7 * HOUR });
    await mk('menunggu', { start: -3 * HOUR, end: HOUR, draw: 2 * HOUR });
    await real.su.query("update giveaways set end_at = now() - interval '1 minute' where id = $1", [ids.menunggu]);
    await mk('selesai', { start: -4 * HOUR });
    await real.su.query("update giveaways set status = 'drawn', end_at = now() - interval '2 hours' where id = $1", [ids.selesai]);
  }, 60_000);
  afterAll(() => real.close());

  it('tanpa kata kunci: aktif (deadline terdekat) lalu akan datang (mulai terdekat); selesai tidak ikut', async () => {
    const list = await api.get('/giveaways');
    expect(titles(list)).toEqual(['Kamera aktif-dekat', 'Kamera aktif-lama', 'Kamera segera-dekat', 'Kamera segera-jauh']);
    expect(list.map((g) => g.status)).toEqual(['active', 'active', 'upcoming', 'upcoming']);
  });

  it('dengan kata kunci: semua status, urut per kelompok', async () => {
    const list = await api.get('/giveaways?q=kamera');
    expect(list.map((g) => g.status)).toEqual(['active', 'active', 'upcoming', 'upcoming', 'waiting_draw', 'drawn']);
    expect(titles(await api.get('/giveaways?q=selesai'))).toEqual(['Kamera selesai']);
  });

  it('kata kunci + sort lain: kelompok status tetap di depan', async () => {
    const list = await api.get('/giveaways?q=kamera&sort=value');
    expect(list.map((g) => g.status)).toEqual(['active', 'active', 'upcoming', 'upcoming', 'waiting_draw', 'drawn']);
    expect(titles(list).slice(0, 2)).toEqual(['Kamera aktif-dekat', 'Kamera aktif-lama']);
  });

  it('status eksplisit dipatuhi persis (juga majemuk dan all), dengan atau tanpa kata kunci', async () => {
    expect(titles(await api.get('/giveaways?status=active'))).toEqual(['Kamera aktif-dekat', 'Kamera aktif-lama']);
    expect(titles(await api.get('/giveaways?status=upcoming&q=kamera'))).toEqual(['Kamera segera-dekat', 'Kamera segera-jauh']);
    expect(titles(await api.get('/giveaways?status=finished'))).toEqual(['Kamera menunggu', 'Kamera selesai']);
    expect(titles(await api.get('/giveaways?status=drawn'))).toEqual(['Kamera selesai']);
    expect((await api.get('/giveaways?status=active,drawn')).map((g) => g.status)).toEqual(['active', 'active', 'drawn']);
    expect(await api.get('/giveaways?status=all')).toHaveLength(6);
  });

  it('status tak dikenal -> invalid_input', async () => {
    expect(await api.get('/giveaways?status=rahasia')).toEqual({ ok: false, error: 'invalid_input', field: 'status' });
    expect(await api.get('/giveaways?status=active,x')).toMatchObject({ ok: false, field: 'status' });
  });

  it('limit/offset tetap: halaman mengikuti urutan kelompok, limit dijepit 1..50', async () => {
    const all = titles(await api.get('/giveaways?q=kamera'));
    const pages = [];
    for (let o = 0; o < 6; o += 4) pages.push(...titles(await api.get(`/giveaways?q=kamera&limit=4&offset=${o}`)));
    expect(pages).toEqual(all);
    expect(await api.get('/giveaways?q=kamera&limit=0')).toHaveLength(1);
    expect(await api.get('/giveaways?q=kamera&limit=999')).toHaveLength(6);
  });

  it('daftar admin tetap terbaru dulu tanpa kelompok status', async () => {
    await register(api, 'admin04', 'admin4@example.com', 'Adm1nPass!', 'Admin');
    await real.su.query("update users set role='admin' where username='admin04'");
    const adm = (await login(api, 'admin04', 'Adm1nPass!')).token;
    const list = await api.get('/admin/giveaways', { token: adm });
    const starts = list.map((g) => new Date(g.start_at).getTime());
    expect(starts).toEqual([...starts].sort((a, b) => b - a));
  });
});
