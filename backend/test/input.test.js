import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createContext, login, makeApi, mkGiveaway, register } from './helpers.js';

// Penguatan validasi masukan (audit keamanan): nilai ekstrem tidak boleh menjadi 500 atau membocorkan galat database.
const real = {};
const api = makeApi(() => real.app);
let adm, tok, uid;

beforeAll(async () => {
  Object.assign(real, await createContext('input'));
  await register(api, 'admin02', 'admin2@example.com', 'Adm1nPass!', 'Admin');
  await real.su.query("update users set role='admin'");
  adm = (await login(api, 'admin02', 'Adm1nPass!')).token;
  await register(api, 'bob0001', 'bob@example.com', 'Passw0rd!1', 'Bob');
  const l = await login(api, 'bob0001', 'Passw0rd!1');
  [tok, uid] = [l.token, l.user.id];
}, 60_000);
afterAll(() => real.close());

describe('GET /giveaways: offset dan deadline_days ekstrem', () => {
  it('offset / deadline_days sangat besar atau negatif -> 200 daftar, bukan 500', async () => {
    await mkGiveaway(api, adm, { title: 'Ada' });
    for (const q of ['offset=99999999999', 'deadline_days=99999999999', 'offset=-5&deadline_days=-9', 'offset=1e15&deadline_days=1e15']) {
      const r = await api.get(`/giveaways?${q}`);
      expect(Array.isArray(r.data ?? r), q).toBe(true);
    }
  });
});

describe('PATCH /me: photo_url', () => {
  it('alamat foto orang lain / URL luar / sembarang ditolak; foto diri sendiri boleh', async () => {
    for (const bad of ['https://evil.example/x.jpg', '/users/00000000-0000-4000-8000-000000000000/photo', `/users/${uid}/photo/../x`, `/users/${uid}/photo?v=abc`, 'javascript:alert(1)']) {
      const r = await api.patch('/me', { token: tok, body: { full_name: 'Bob', photo_url: bad } });
      expect([r.ok, r.error], bad).toEqual([false, 'invalid_input']);
    }
    const good = await api.patch('/me', { token: tok, body: { full_name: 'Bob', photo_url: `/users/${uid}/photo?v=123` } });
    expect(good.ok).toBe(true);
    expect(good.user.photo_url).toBe(`/users/${uid}/photo?v=123`);
  });
});

describe('admin upsert dan system_events', () => {
  it('galat database pada input -> invalid_input tanpa detail dari driver', async () => {
    const r = await mkGiveaway(api, adm, { title: 'Terlalu mahal', prize_value_usd: 1e20 });
    expect(r).toMatchObject({ ok: false, error: 'invalid_input' });
    expect(r).not.toHaveProperty('detail');
  });
});
