import { afterAll, beforeAll } from 'vitest';
import { createContext, makeApi } from './helpers.js';
import { authSections } from './sections/auth.js';
import { giveawaySections } from './sections/giveaway.js';
import { drawSections } from './sections/draw.js';
import { redeemSections } from './sections/redeem.js';
import { accessSection, featureSection, searchSection } from './sections/rest.js';

// Port test_m1.py ke API HTTP. Bagian-bagian berbagi state (alice, admin, giveaway) dan
// berjalan berurutan dalam satu database uji. Section didaftarkan sebelum beforeAll berjalan,
// jadi ctx berisi pembungkus yang menunjuk ke koneksi asli saat tes dieksekusi.
const real = {};
const wrap = (name) => ({ query: (...a) => real[name].query(...a) });
const ctx = {
  s: {},
  api: makeApi(() => real.app),
  su: wrap('su'),
  anon: wrap('anon'),
  real,
};

beforeAll(async () => {
  Object.assign(real, await createContext('api'));
}, 60_000);
afterAll(() => real.close());

authSections(ctx);
giveawaySections(ctx);
redeemSections(ctx);
searchSection(ctx);
drawSections(ctx);
featureSection(ctx);
accessSection(ctx);
