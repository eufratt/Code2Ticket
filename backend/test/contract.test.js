import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { blockHash, ownerKey, pickWinners, ticketsHash } from '../src/lib/chain.js';
import { sha256Hex } from '../src/lib/util.js';
import { clientHash, createContext, genCodes, login, makeApi, mkGiveaway, redeem, register, SCHEMA_DIR } from './helpers.js';

// Tes kontrak: hasil Node HARUS sama dengan implementasi acuan Python (test_m1.py) untuk input yang sama.
const HERE = path.dirname(fileURLToPath(import.meta.url));
const REF = process.env.CONTRACT_REF ?? path.join(HERE, 'reference/test_m1.py');
const VECTORS = path.join(HERE, 'contract_vectors.py');

function python(request) {
  const errors = [];
  for (const cmd of [process.env.PYTHON, 'python', 'python3', 'py'].filter(Boolean)) {
    const r = spawnSync(cmd, ['-I', VECTORS, REF], { input: JSON.stringify(request), encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
    if (r.error) { errors.push(`${cmd}: ${r.error.message}`); continue; }
    if (r.status !== 0) throw new Error(`Python gagal (${cmd}): ${r.stderr}`);
    return JSON.parse(r.stdout);
  }
  throw new Error(`Python 3 tidak ditemukan (set env PYTHON): ${errors.join('; ')}`);
}

// PRNG deterministik agar kegagalan dapat diulang.
function prng(seed) {
  let x = BigInt(seed);
  return () => {
    x = (x * 6364136223846793005n + 1442695040888963407n) & ((1n << 64n) - 1n);
    return Number(x >> 11n) / 2 ** 53;
  };
}
const rnd = prng(20260101);
const hex = (n) => Array.from({ length: n }, () => Math.floor(rnd() * 16).toString(16)).join('');
const uuid = () => `${hex(8)}-${hex(4)}-4${hex(3)}-8${hex(3)}-${hex(12)}`;

function makeTickets(n, owners) {
  const keys = Array.from({ length: owners }, () => hex(12));
  return Array.from({ length: n }, (_, i) => [i + 1, keys[Math.floor(rnd() * owners)]]);
}

describe('kontrak hash block, pemenang, dan hash klien (Node = Python acuan)', () => {
  const picks = [];
  for (let i = 0; i < 250; i++) {
    const n = Math.floor(rnd() * 70);
    const owners = 1 + Math.floor(rnd() * Math.max(1, n));
    picks.push({ seed: hex(64), gid: uuid(), tickets: makeTickets(n, owners), k: 1 + Math.floor(rnd() * 12) });
  }
  // kasus tepi: kosong, satu tiket, semua tiket satu pemilik, k > peserta unik
  picks.push({ seed: hex(64), gid: uuid(), tickets: [], k: 3 });
  picks.push({ seed: hex(64), gid: uuid(), tickets: [[1, 'aaaaaaaaaaaa']], k: 5 });
  picks.push({ seed: hex(64), gid: uuid(), tickets: Array.from({ length: 9 }, (_, i) => [i + 1, 'bbbbbbbbbbbb']), k: 5 });
  picks.push({ seed: 'f'.repeat(64), gid: uuid(), tickets: makeTickets(100, 100), k: 100 });
  picks.push({ seed: '0'.repeat(64), gid: uuid(), tickets: makeTickets(100, 100), k: 100 });

  const blocks = [];
  for (let i = 0; i < 60; i++) {
    const common = { block_index: i + 1, giveaway_id: uuid(), ts_ms: 1_700_000_000_000 + Math.floor(rnd() * 1e9), previous_hash: hex(64) };
    blocks.push(
      i % 2 === 0
        ? { ...common, block_type: 'commit', seed_hash: hex(64), winner_count: 1 + Math.floor(rnd() * 100) }
        : {
            ...common, block_type: 'result', draw_id: uuid(), seed: hex(64), total_tickets: Math.floor(rnd() * 5000),
            tickets_hash: hex(64), winning_tickets: i % 7 === 1 ? '' : [1, 22, 333, 4444].slice(0, 1 + (i % 4)).join(','),
          },
    );
  }
  const logins = Array.from({ length: 12 }, (_, i) => [`Pässw0rd!${i}${'x'.repeat(i)}`, hex(32)]);
  const owners = Array.from({ length: 20 }, () => [uuid(), uuid()]);

  const ref = python({ picks, blocks, client_hash: logins, owner_key: owners, sha: ['', 'abc', hex(64)] });

  it('hash block (commit dan result) identik dengan Python', () => {
    expect(blocks.map(blockHash)).toEqual(ref.block_hash);
  });
  it('tickets_hash dan daftar pemenang identik dengan Python (250+ kasus, BigInt 56 bit)', () => {
    const mine = picks.map((c) => {
      const r = pickWinners(c.seed, c.gid, c.tickets, c.k);
      return { tickets_hash: r.ticketsHash, winners: r.winners };
    });
    expect(mine).toEqual(ref.picks);
    expect(picks.map((c) => ticketsHash(c.tickets))).toEqual(ref.picks.map((p) => p.tickets_hash));
  });
  it('kasus pemenang sungguhan mencakup nilai di atas 2^53 (BigInt diperlukan)', () => {
    let big = 0;
    for (const c of picks.slice(0, 60)) {
      for (let j = 0; j < 4; j++) {
        const h = sha256Hex(`${c.seed}:${c.gid}:${ticketsHash(c.tickets)}:${j}`);
        if (BigInt('0x' + h.slice(0, 14)) > 2n ** 53n) big += 1;
      }
    }
    expect(big).toBeGreaterThan(0);
  });
  it('owner_key identik dengan Python', () => {
    expect(owners.map(([u, g]) => ownerKey(u, g))).toEqual(ref.owner_key);
  });
  it('SHA-256 identik dengan Python', () => {
    expect(['', 'abc'].map(sha256Hex)).toEqual(ref.sha.slice(0, 2));
  });
  it('hash password klien (PBKDF2) identik dengan Python', () => {
    expect(logins.map(([pw, salt]) => clientHash(pw, salt))).toEqual(ref.client_hash);
  });
  it('vektor tetap (known-answer) tidak berubah', () => {
    expect(sha256Hex('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(blockHash({ block_type: 'commit', block_index: 1, giveaway_id: 'g', seed_hash: 's', winner_count: 2, ts_ms: 3, previous_hash: '0'.repeat(64) }))
      .toBe(sha256Hex(`C|1|g|s|2|3|${'0'.repeat(64)}`));
  });
});

describe('data dari API diverifikasi oleh verify() Python acuan', () => {
  const real = {};
  const api = makeApi(() => real.app);
  beforeAll(async () => Object.assign(real, await createContext('contract')), 60_000);
  afterAll(() => real.close());

  it('hasil draw Node lolos verify() Python; manipulasi terdeteksi', async () => {
    await register(api, 'admin01', 'admin@example.com', 'Adm1nPass!', 'Admin');
    await real.su.query("update users set role='admin'");
    const adm = (await login(api, 'admin01', 'Adm1nPass!')).token;
    const g = await mkGiveaway(api, adm, { title: 'Kontrak', winners: 4, maxTickets: 6 });
    const codes = await genCodes(api, adm, g.giveaway_id, 40);
    let k = 0;
    for (let i = 0; i < 8; i++) {
      await register(api, `peserta${i}`, `p${i}@example.com`, 'Passw0rd!1', `P${i}`);
      const tok = (await login(api, `peserta${i}`, 'Passw0rd!1')).token;
      for (let j = 0; j < 1 + (i % 4); j++) await redeem(api, tok, codes[k++]);
    }
    const before = await api.get(`/giveaways/${g.giveaway_id}/verification`);
    expect(python({ verify: before }).verify).toEqual({ ok: true, why: 'belum di-draw (seed masih terkunci)' });

    const d = await api.post(`/admin/giveaways/${g.giveaway_id}/draw`, { token: adm });
    expect(d.ok).toBe(true);
    const after = await api.get(`/giveaways/${g.giveaway_id}/verification`);
    expect(python({ verify: after }).verify).toEqual({ ok: true, why: 'valid' });

    const forged = JSON.parse(JSON.stringify(after));
    forged.chain.find((b) => b.block_type === 'result').winning_tickets = '1,2,3,4';
    expect(python({ verify: forged }).verify.ok).toBe(false);
    const swapped = JSON.parse(JSON.stringify(after));
    swapped.tickets.reverse();
    expect(python({ verify: swapped }).verify.ok).toBe(false);
  });

  it('seed rahasia tidak bocor lewat endpoint publik sebelum draw', async () => {
    const adm = (await login(api, 'admin01', 'Adm1nPass!')).token;
    const g = await mkGiveaway(api, adm, { title: 'Rahasia' });
    const { seed } = (await real.su.query('select seed from giveaway_secrets where giveaway_id=$1', [g.giveaway_id])).rows[0];
    const dump = JSON.stringify([
      await api.get(`/giveaways/${g.giveaway_id}/verification`),
      await api.get(`/giveaways/${g.giveaway_id}/winners`),
      await api.get('/giveaways', { query: { status: 'all' } }),
      await api.get(`/admin/giveaways/${g.giveaway_id}/codes`, { token: adm }),
    ]);
    expect(dump).not.toContain(seed);
  });
});
