import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createContext, login, makeApi, register } from './helpers.js';

const real = {};
const api = makeApi(() => real.app);
let tok;

beforeAll(async () => {
  Object.assign(real, await createContext('gamescore'));
  await register(api, 'gamer01', 'gamer@example.com', 'Passw0rd!1', 'Gamer');
  tok = (await login(api, 'gamer01', 'Passw0rd!1')).token;
}, 60_000);
afterAll(() => real.close());

const post = (stars, left, cleared, dur) =>
  api.post('/game/scores', { token: tok, body: { stars, seconds_left: left, cleared, duration_sec: dur } });
const rows = async () => (await real.su.query('select count(*)::int n from game_scores')).rows[0].n;

describe('POST /game/scores: validasi kewajaran', () => {
  it('hasil sah di tiap tingkat (termasuk gagal waktu habis) diterima', async () => {
    const legit = [
      [5, 30, true, 28], // Mudah, selesai
      [8, 10, true, 44], // Sedang
      [12, 5, true, 44], // Sulit, semua bintang
      [3, 0, false, 50], // Sulit, waktu habis
      [0, 0, false, 60], // Mudah, waktu habis tanpa bintang
      [0, 20, true, 40], // selesai tanpa bintang
    ];
    for (const s of legit) expect((await post(...s)).ok, JSON.stringify(s)).toBe(true);
  });

  it('data curang ditolak invalid_score dan tidak tersimpan', async () => {
    const before = await rows();
    const cheats = [
      [13, 0, true, 40], // bintang melebihi item semua tingkat
      [6, 55, true, 5], // sisa waktu 55 + 5 detik main, tapi 6 bintang butuh tingkat Sedang (55 dtk): 60 > 57
      [5, 61, true, 10], // sisa waktu > 60 (di atas batas skema: invalid_input)
      [5, 50, true, 30], // lama main + sisa waktu 80 > 60
      [5, 30, true, 1], // terlalu singkat untuk menyelesaikan
      [12, 40, true, 6], // 12 bintang dalam 6 detik
      [12, 45, true, 10], // 12 bintang hanya di tingkat Sulit (50 dtk): 55 > 52
    ];
    for (const s of cheats) {
      const r = await post(...s);
      expect(r.ok, JSON.stringify(s)).toBe(false);
      expect(['invalid_score', 'invalid_input']).toContain(r.error);
    }
    expect((await post(13, 0, true, 40)).error).toBe('invalid_score');
    expect(await rows()).toBe(before);
  });

  it('batas kiriman per jam -> too_many_requests', async () => {
    const have = await rows();
    for (let i = have; i < 60; i++) await real.su.query('insert into game_scores(user_id, score, stars, duration_sec) select id, 0, 0, 60 from users limit 1');
    const r = await post(1, 10, true, 30);
    expect([r.ok, r.error]).toEqual([false, 'too_many_requests']);
    await real.su.query("update game_scores set created_at = now() - interval '2 hours'");
    expect((await post(1, 10, true, 30)).ok).toBe(true);
  });
});
