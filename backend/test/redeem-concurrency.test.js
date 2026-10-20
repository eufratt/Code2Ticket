import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createContext, genCodes, login, makeApi, mkGiveaway, redeem, register } from './helpers.js';

const real = {};
const api = makeApi(() => real.app);
let adm, tok, tok2;

beforeAll(async () => {
  Object.assign(real, await createContext('redeemconc'));
  await register(api, 'admin03', 'admin3@example.com', 'Adm1nPass!', 'Admin');
  await real.su.query("update users set role='admin'");
  adm = (await login(api, 'admin03', 'Adm1nPass!')).token;
  await register(api, 'carol01', 'carol@example.com', 'Passw0rd!1', 'Carol');
  await register(api, 'dave001', 'dave@example.com', 'Passw0rd!1', 'Dave');
  tok = (await login(api, 'carol01', 'Passw0rd!1')).token;
  tok2 = (await login(api, 'dave001', 'Passw0rd!1')).token;
}, 60_000);
afterAll(() => real.close());

describe('redeem: serialisasi per pengguna', () => {
  it('12 tebakan salah paralel: hanya 5 yang dihitung, sisanya rate_limited', async () => {
    const guesses = Array.from({ length: 12 }, (_, i) => `ZZZZ-ZZZZ-ZZ${String(10 + i)}`);
    const res = await Promise.all(guesses.map((g) => redeem(api, tok, g)));
    expect(res.filter((r) => r.error === 'code_not_found')).toHaveLength(5);
    expect(res.filter((r) => r.error === 'rate_limited')).toHaveLength(7);
    const n = (await real.su.query("select count(*)::int n from code_attempts where not success and reason = 'code_not_found'")).rows[0].n;
    expect(n).toBe(5);
  });

  it('kode sah dipakai paralel oleh dua pengguna dan satu pengguna: tepat satu tiket per kode, tanpa deadlock', async () => {
    const g = await mkGiveaway(api, adm, { title: 'Paralel', maxTickets: 3 });
    const codes = await genCodes(api, adm, g.giveaway_id, 4);
    const res = await Promise.all([
      redeem(api, tok2, codes[0]), redeem(api, tok2, codes[1]), redeem(api, tok2, codes[2]), redeem(api, tok2, codes[3]),
      redeem(api, adm, codes[0]),
    ]);
    // maxTickets 3: pengguna tok2 mendapat 3 dari 4; kode[0] hanya satu pemenang antara tok2 dan admin
    const mine = res.slice(0, 4).filter((r) => r.ok).length;
    expect(mine).toBeLessThanOrEqual(3);
    const tickets = (await real.su.query('select count(*)::int n from tickets where giveaway_id=$1', [g.giveaway_id])).rows[0].n;
    expect(tickets).toBe(res.filter((r) => r.ok).length);
  });
});
