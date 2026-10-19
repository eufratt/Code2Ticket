import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { createContext, genCodes, HOUR, login, makeApi, mkGiveaway, redeem, register } from './helpers.js';

// M8a: utang teknis backend. Satu database uji untuk semua bagian; tiap describe memuat satu perbaikan.
const real = {};
const api = makeApi(() => real.app);
let adm;
let alice;
const one = async (sql, params) => (await real.su.query(sql, params)).rows[0];
const count = async (sql, params) => (await one(sql, params)).n;
const iso = (ms) => new Date(Date.now() + ms).toISOString();

beforeAll(async () => {
  Object.assign(real, await createContext('debt'));
  await register(api, 'admin01', 'admin@example.com', 'Adm1nPass!', 'Admin');
  await real.su.query("update users set role='admin'");
  adm = (await login(api, 'admin01', 'Adm1nPass!')).token;
  await register(api, 'alice01', 'alice@example.com', 'Passw0rd!1', 'Alice');
  alice = (await login(api, 'alice01', 'Passw0rd!1')).token;
}, 60_000);
afterAll(() => real.close());

describe('1. status giveaway dihitung saat dibaca (tanpa menunggu tick)', () => {
  const ids = {};
  // Kolom status sengaja dibuat basi: scheduler belum berjalan.
  const stale = (id, start, end, draw, status) =>
    real.su.query('update giveaways set start_at=$2, end_at=$3, draw_at=$4, status=$5 where id=$1', [id, iso(start), iso(end), iso(draw), status]);

  beforeAll(async () => {
    for (const k of ['running', 'over', 'future', 'done']) ids[k] = (await mkGiveaway(api, adm, { title: `S-${k}` })).giveaway_id;
    await stale(ids.running, -2 * HOUR, HOUR, 2 * HOUR, 'upcoming'); // sudah mulai, kolom masih upcoming
    await stale(ids.over, -3 * HOUR, -HOUR, HOUR, 'active'); // sudah berakhir, kolom masih active
    await stale(ids.future, 2 * HOUR, 3 * HOUR, 4 * HOUR, 'active'); // belum mulai, kolom salah
    await stale(ids.done, -3 * HOUR, -2 * HOUR, -HOUR, 'drawn');
  });

  it('GET /giveaways/:id', async () => {
    const st = async (k) => (await api.get(`/giveaways/${ids[k]}`)).status;
    expect([await st('running'), await st('over'), await st('future'), await st('done')]).toEqual(['active', 'waiting_draw', 'upcoming', 'drawn']);
  });

  it('GET /giveaways (daftar, semua filter status) sama dengan detail', async () => {
    const all = await api.get('/giveaways', { query: { status: 'all', limit: 50 } });
    const by = Object.fromEntries(all.map((g) => [g.title, g.status]));
    expect(by).toMatchObject({ 'S-running': 'active', 'S-over': 'waiting_draw', 'S-future': 'upcoming', 'S-done': 'drawn' });
  });

  it('GET /tickets: giveaway_status ikut dihitung', async () => {
    await stale(ids.running, -2 * HOUR, HOUR, 2 * HOUR, 'active');
    const codes = await genCodes(api, adm, ids.running, 1);
    expect((await redeem(api, alice, codes[0])).ok).toBe(true);
    await stale(ids.running, -3 * HOUR, -HOUR, HOUR, 'active'); // berakhir tanpa tick
    const t = await api.get('/tickets', { token: alice });
    expect(t[0].giveaway_status).toBe('waiting_draw');
  });
});

describe('2. seed_mismatch pada draw terjadwal tidak diulang tiap menit', () => {
  const ids = {};
  const makeDue = async (title, tickets) => {
    const id = (await mkGiveaway(api, adm, { title })).giveaway_id;
    const codes = await genCodes(api, adm, id, tickets);
    for (const c of codes) expect((await redeem(api, alice, c)).ok).toBe(true);
    await real.su.query('update giveaways set start_at=$2, end_at=$3, draw_at=$4 where id=$1', [id, iso(-3 * HOUR), iso(-2 * HOUR), iso(-HOUR)]);
    return id;
  };

  beforeAll(async () => {
    ids.bad = await makeDue('Rusak', 2);
    ids.good = await makeDue('Sehat', 2);
    await real.su.query('update giveaway_secrets set seed = $2 where giveaway_id = $1', [ids.bad, 'f'.repeat(64)]);
  });

  it('dicoba sekali, dicatat sekali; menit-menit berikutnya dilewati', async () => {
    const { runDueDraws } = await import('../src/services/draw.js');
    expect(await runDueDraws(real.pool)).toBe(1); // yang sehat tetap terundi
    for (let i = 0; i < 3; i++) expect(await runDueDraws(real.pool)).toBe(0);
    expect(await count("select count(*)::int n from system_events where event='draw_seed_mismatch' and details->>'giveaway_id' = $1", [ids.bad])).toBe(1);
  });

  it('draw_chain tidak tersentuh: tanpa draw, pemenang, atau block hasil untuk yang rusak', async () => {
    expect(await count('select count(*)::int n from draws where giveaway_id=$1', [ids.bad])).toBe(0);
    expect(await count("select count(*)::int n from draw_chain where giveaway_id=$1 and block_type='result'", [ids.bad])).toBe(0);
    expect(await count("select count(*)::int n from draw_chain where giveaway_id=$1 and block_type='result'", [ids.good])).toBe(1);
    const { verifyChain } = await import('../src/lib/chain.js');
    expect((await verifyChain(real.su)).every((r) => r.ok)).toBe(true);
  });

  it('admin tetap bisa mencoba draw manual (dilaporkan seed_mismatch), dan hanya event hapus yang membuka scheduler lagi', async () => {
    const r = await api.post(`/admin/giveaways/${ids.bad}/draw`, { token: adm });
    expect(r.error).toBe('seed_mismatch');
    const { runDueDraws } = await import('../src/services/draw.js');
    expect(await runDueDraws(real.pool)).toBe(0);
  });
});

describe('3. kegagalan sah tidak dihitung ke batas 5 kegagalan redeem', () => {
  let carl;
  const lock = () => count("select count(*)::int n from code_attempts a join users u on u.id=a.user_id where u.username='carl01' and not a.success and a.reason in ('invalid_format','code_not_found','code_used')");

  beforeAll(async () => {
    await register(api, 'carl01', 'carl@example.com', 'Passw0rd!1', 'Carl');
    carl = (await login(api, 'carl01', 'Passw0rd!1')).token;
  });

  it('alasan sah berulang (> 5x) tidak mengunci; kode benar sesudahnya tetap diterima', async () => {
    const limit1 = (await mkGiveaway(api, adm, { title: 'Satu tiket', maxTickets: 1 })).giveaway_id;
    const c1 = await genCodes(api, adm, limit1, 3);
    const geo = (await mkGiveaway(api, adm, { title: 'Geo', lat: -6.2, lng: 106.8 })).giveaway_id;
    const cg = await genCodes(api, adm, geo, 1, [-6.2, 106.8, 5]);
    const future = (await mkGiveaway(api, adm, { title: 'Belum mulai' })).giveaway_id;
    const cf = await genCodes(api, adm, future, 1);
    await real.su.query('update giveaways set start_at=$2, end_at=$3, draw_at=$4 where id=$1', [future, iso(HOUR), iso(2 * HOUR), iso(3 * HOUR)]);
    const over = (await mkGiveaway(api, adm, { title: 'Berakhir' })).giveaway_id;
    const co = await genCodes(api, adm, over, 1);
    await real.su.query('update giveaways set start_at=$2, end_at=$3, draw_at=$4 where id=$1', [over, iso(-3 * HOUR), iso(-2 * HOUR), iso(-HOUR)]);

    expect((await redeem(api, carl, c1[0])).ok).toBe(true);
    const expected = [
      [c1[1], 'ticket_limit'], [c1[0], 'code_used'], [cg[0], 'location_required'], [cg[0], 'out_of_area', -6.9175, 107.6191],
      [cf[0], 'giveaway_not_started'], [co[0], 'giveaway_ended'],
    ];
    for (let round = 0; round < 2; round++) {
      for (const [code, err, lat, lng] of expected) expect((await redeem(api, carl, code, lat, lng)).error).toBe(err); // kode ke klien tidak berubah
    }
    expect(await lock()).toBe(0);
    const fresh = (await mkGiveaway(api, adm, { title: 'Giveaway lain' })).giveaway_id;
    expect((await redeem(api, carl, (await genCodes(api, adm, fresh, 1))[0])).ok).toBe(true);
  });

  it('tebakan salah tetap dihitung: kegagalan ke-6 -> rate_limited, walau kode benar', async () => {
    for (let i = 0; i < 3; i++) expect((await redeem(api, carl, `ZZZZ-ZZZZ-ZZZ${i}`)).error).toBe('code_not_found');
    expect((await redeem(api, carl, 'bukan kode')).error).toBe('invalid_format');
    const alicesGw = (await mkGiveaway(api, adm, { title: 'Milik alice' })).giveaway_id;
    const [ac, spare] = await genCodes(api, adm, alicesGw, 2);
    expect((await redeem(api, alice, ac)).ok).toBe(true);
    expect((await redeem(api, carl, ac)).error).toBe('code_used'); // kode orang lain = tebakan, dihitung (kegagalan ke-5)
    expect(await lock()).toBe(5);
    const r = await redeem(api, carl, spare);
    expect(r.error).toBe('rate_limited');
    expect(r.retry_after_seconds).toBeGreaterThan(0);
  });
});
