import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { keccak256, parseTransaction, recoverTransactionAddress, toHex } from 'viem';
import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts';
import {
  BACKEND_SQL, ORGANIZER_CONTACT_SQL, PARTICIPATION_SQL, PHOTOS_SQL, PRIZE_IDR_SQL, REDEEM_GEO_SQL,
  createContext, genCodes, login, makeApi, mkGiveaway, redeem, register,
} from './helpers.js';
import { MAX_ATTEMPTS, anchorData, anchorSettings, backoffSeconds, publicLinks, redact, startAnchor, stopAnchor, viemClient } from '../src/services/anchor.js';
import { executeDraw } from '../src/services/draw.js';

// Tanpa jaringan nyata: RPC JSON tiruan lewat fetchFn viem. Kunci dibuat acak saat tes (tidak ada kunci di repo).
const KEY = generatePrivateKey();
const WALLET = privateKeyToAccount(KEY).address;
const RPC_KEY = 'SECRETRPCKEY0123456789';
const RPC_URL = `https://rpc.example.test/v2/${RPC_KEY}`;
const env = (over = {}) => ({
  ANCHOR_ENABLED: 'true', ANCHOR_RPC_URL: RPC_URL, ANCHOR_CHAIN_ID: '80002', ANCHOR_PRIVATE_KEY: KEY, ...over,
});

function mockRpc(chainId = 80002) {
  const st = { down: false, drop: false, pending: 0, latest: 0, txs: new Map(), mined: new Set(), sent: [], calls: [] };
  async function handle(method, p) {
    st.calls.push(method);
    switch (method) {
      case 'eth_chainId': return toHex(chainId);
      case 'eth_getTransactionCount': return toHex(p[1] === 'latest' ? st.latest : st.pending);
      case 'eth_getBlockByNumber':
        return { number: '0x10', hash: `0x${'1'.repeat(64)}`, parentHash: `0x${'0'.repeat(64)}`, timestamp: '0x1',
          baseFeePerGas: '0x3b9aca00', gasLimit: '0x1c9c380', gasUsed: '0x0', transactions: [] };
      case 'eth_maxPriorityFeePerGas': case 'eth_gasPrice': return '0x3b9aca00';
      case 'eth_estimateGas': return '0x5208';
      case 'eth_sendRawTransaction': {
        const tx = parseTransaction(p[0]);
        const hash = keccak256(p[0]);
        const from = await recoverTransactionAddress({ serializedTransaction: p[0] });
        st.sent.push({ hash, tx, from });
        if (!st.drop) { st.txs.set(hash, { hash, input: tx.data, from, to: tx.to }); st.pending = Math.max(st.pending, tx.nonce + 1); }
        return hash;
      }
      case 'eth_getTransactionByHash': return st.txs.get(p[0]) ?? null;
      case 'eth_getTransactionReceipt': return st.mined.has(p[0]) ? { transactionHash: p[0], status: '0x1', blockNumber: '0x11' } : null;
      default: throw new Error(`metode tak dikenal ${method}`);
    }
  }
  st.fetchFn = async (url, init) => {
    if (st.down) throw new TypeError(`fetch failed ${url}`);
    const req = JSON.parse(init.body);
    const result = await handle(req.method, req.params);
    return new Response(JSON.stringify({ jsonrpc: '2.0', id: req.id, result }), { headers: { 'content-type': 'application/json' } });
  };
  st.mine = () => { for (const h of st.txs.keys()) st.mined.add(h); st.latest = st.pending; };
  return st;
}

const MIGRATIONS_BEFORE_12 = [BACKEND_SQL, PHOTOS_SQL, PRIZE_IDR_SQL, PARTICIPATION_SQL, REDEEM_GEO_SQL, ORGANIZER_CONTACT_SQL];

async function setup(real, api, name, migrations) {
  Object.assign(real, await createContext(name, {}, migrations));
  await register(api, 'admin01', 'admin@example.test', 'Adm1nPass!', 'Admin');
  await real.su.query("update users set role='admin'");
  return (await login(api, 'admin01', 'Adm1nPass!')).token;
}

describe('jangkar blockchain', () => {
  const real = {};
  const api = makeApi(() => real.app);
  let adm;
  let rpc;
  let logs;
  let anchor;

  // Tiap tes mulai dari antrean kosong supaya baris tes sebelumnya tidak ikut diproses.
  const start = async (over = {}) => {
    await real.su.query('delete from chain_anchors');
    logs = [];
    rpc = mockRpc();
    anchor = startAnchor({
      pool: real.pool, config: env(over), log: (l) => logs.push(l), intervalMs: 0,
      client: viemClient({ ...anchorSettings(env(over)), fetchFn: rpc.fetchFn, retryCount: 0 }),
    });
    return anchor;
  };
  const rows = async () => (await real.su.query('select a.*, d.block_type from chain_anchors a join draw_chain d on d.id = a.chain_block_id order by a.id')).rows;
  const rowOf = async (gid, type) =>
    (await real.su.query('select a.* from chain_anchors a join draw_chain d on d.id = a.chain_block_id where d.giveaway_id = $1 and d.block_type = $2', [gid, type])).rows[0];
  const settle = async () => { await new Promise((r) => setImmediate(r)); await anchor.runOnce(); };

  beforeAll(async () => { adm = await setup(real, api, 'anchor'); }, 60_000);
  afterEach(() => stopAnchor());
  afterAll(() => real.close());

  it('konfigurasi: ANCHOR_ENABLED bukan true atau nilai kurang = mati tanpa crash', () => {
    expect(anchorSettings({})).toBeNull();
    expect(anchorSettings(env({ ANCHOR_ENABLED: 'yes' }))).toBeNull();
    expect(anchorSettings(env({ ANCHOR_PRIVATE_KEY: '' }))).toBeNull();
    expect(anchorSettings(env({ ANCHOR_PRIVATE_KEY: 'bukan-kunci' }))).toBeNull();
    expect(anchorSettings(env({ ANCHOR_RPC_URL: '' }))).toBeNull();
    expect(anchorSettings(env({ ANCHOR_CHAIN_ID: 'abc' }))).toBeNull();
    expect(anchorSettings(env({ ANCHOR_PRIVATE_KEY: KEY.slice(2) })).privateKey).toBe(KEY);
    const l = [];
    expect(startAnchor({ pool: real.pool, config: env({ ANCHOR_PRIVATE_KEY: '' }), log: (x) => l.push(x) })).toBeNull();
    expect(l.join('\n')).toContain('tidak lengkap');
  });

  it('fitur mati: giveaway dan draw tetap jalan, tidak ada baris jangkar, API "none"', async () => {
    const gid = (await mkGiveaway(api, adm)).giveaway_id;
    expect((await executeDraw(real.pool, gid, 'admin_demo')).ok).toBe(true);
    expect((await real.su.query('select count(*)::int as n from chain_anchors')).rows[0].n).toBe(0);
    const r = await api.get(`/giveaways/${gid}/anchors`);
    expect(r.ok).toBe(true);
    expect(r.anchors.map((a) => [a.block_type, a.status, a.tx_hash])).toEqual([['commit', 'none', null], ['result', 'none', null]]);
  });

  it('blok Commit dijangkarkan otomatis setelah giveaway dibuat: tx value 0 ke dompet sendiri, data C2T:hash', async () => {
    await start();
    const gid = (await mkGiveaway(api, adm)).giveaway_id;
    await vi.waitFor(() => expect(rpc.sent).toHaveLength(1)); // dipicu kickAnchor, tanpa runOnce manual
    const commit = (await real.su.query("select * from draw_chain where giveaway_id = $1 and block_type = 'commit'", [gid])).rows[0];
    const { tx, from, hash } = rpc.sent[0];
    expect(tx.data).toBe(toHex(`C2T:${commit.block_hash}`));
    expect(tx.data).toBe(anchorData(commit.block_hash));
    expect(tx.to.toLowerCase()).toBe(WALLET.toLowerCase());
    expect(from.toLowerCase()).toBe(WALLET.toLowerCase());
    expect(tx.value ?? 0n).toBe(0n);
    expect(tx.chainId).toBe(80002);
    await vi.waitFor(async () => expect((await rowOf(gid, 'commit'))?.tx_hash).toBe(hash));
    const row = await rowOf(gid, 'commit');
    expect(row).toMatchObject({ status: 'pending', attempts: 1, block_hash: commit.block_hash, chain_id: 80002 });

    rpc.mine();
    await real.su.query('update chain_anchors set next_attempt_at = now()');
    await anchor.runOnce();
    expect(await rowOf(gid, 'commit')).toMatchObject({ status: 'confirmed', tx_hash: hash });
    expect((await rowOf(gid, 'commit')).confirmed_at).not.toBeNull();

    const a = (await api.get(`/giveaways/${gid}/anchors`)).anchors[0];
    expect(a).toEqual({
      block_index: commit.block_index, block_type: 'commit', block_hash: commit.block_hash, tx_hash: hash, chain_id: 80002,
      status: 'confirmed', explorer_url: `https://amoy.polygonscan.com/tx/${hash}`, rpc_url: 'https://rpc-amoy.polygon.technology',
    });
  });

  it('blok Hasil dijangkarkan setelah draw', async () => {
    await start();
    const gid = (await mkGiveaway(api, adm)).giveaway_id;
    await settle();
    expect((await executeDraw(real.pool, gid, 'admin_demo')).ok).toBe(true);
    await settle();
    const result = await rowOf(gid, 'result');
    expect(result).toMatchObject({ status: 'pending', attempts: 1 });
    const block = (await real.su.query("select block_hash from draw_chain where giveaway_id = $1 and block_type = 'result'", [gid])).rows[0];
    expect(rpc.sent.at(-1).tx.data).toBe(anchorData(block.block_hash));
    const r = (await api.get(`/giveaways/${gid}/anchors`)).anchors;
    expect(r.map((a) => a.block_type)).toEqual(['commit', 'result']);
    expect(r[1]).toMatchObject({ tx_hash: result.tx_hash, status: 'pending', chain_id: 80002 });
  });

  it('tautan publik: env menimpa bawaan; RPC ber-key/berkredensial/http tidak pernah dikirim ke klien', () => {
    const c = env({ ANCHOR_EXPLORER_TX_URL: 'https://explorer.example.test/tx/{tx}', ANCHOR_PUBLIC_RPC_URL: 'https://public-rpc.example.test' });
    expect(publicLinks(c, 80002).rpcUrl).toBe('https://public-rpc.example.test/');
    expect(publicLinks(c, 80002).explorer('0xab')).toBe('https://explorer.example.test/tx/0xab');
    expect(publicLinks(env(), 80002).rpcUrl).toBe('https://rpc-amoy.polygon.technology'); // bukan ANCHOR_RPC_URL ber-key
    expect(publicLinks(env({ ANCHOR_PUBLIC_RPC_URL: 'https://u:p@rpc.example.test' }), 80002).rpcUrl).toBe('https://rpc-amoy.polygon.technology');
    expect(publicLinks(env({ ANCHOR_PUBLIC_RPC_URL: 'http://rpc.example.test' }), 80002).rpcUrl).toBe('https://rpc-amoy.polygon.technology');
    expect(publicLinks(env({ ANCHOR_CHAIN_ID: '1234' }), 1234)).toMatchObject({ rpcUrl: null });
    expect(publicLinks(env({ ANCHOR_CHAIN_ID: '1234' }), 1234).explorer('0xab')).toBeNull();
    expect(publicLinks(env({ ANCHOR_EXPLORER_TX_URL: 'javascript:alert({tx})' }), 80002).explorer('0xab')).toBeNull();
  });

  it('idempoten: putaran berulang/bersamaan dan antrean ganda tidak mengirim transaksi kedua untuk blok yang sama', async () => {
    await start();
    const gid = (await mkGiveaway(api, adm)).giveaway_id;
    await Promise.all([anchor.runOnce(), anchor.runOnce(), settle()]);
    await real.su.query('update chain_anchors set next_attempt_at = now()');
    await anchor.runOnce(); // tx_hash sudah ada -> hanya cek receipt, tidak kirim ulang
    await anchor.runOnce();
    const data = anchorData((await rowOf(gid, 'commit')).block_hash);
    const mine = rpc.sent.filter((s) => s.tx.data === data);
    expect(mine).toHaveLength(1);
    // Antre ulang blok yang sama (mis. dua proses) tidak membuat baris baru.
    const blockId = (await rowOf(gid, 'commit')).chain_block_id;
    await real.su.query('insert into chain_anchors(chain_block_id, block_hash, chain_id) select id, block_hash, 80002 from draw_chain where id = $1 on conflict (chain_block_id) do nothing', [blockId]);
    expect((await real.su.query('select count(*)::int as n from chain_anchors where chain_block_id = $1', [blockId])).rows[0].n).toBe(1);
    await expect(real.su.query('insert into chain_anchors(chain_block_id, block_hash, chain_id) select id, block_hash, 80002 from draw_chain where id = $1', [blockId]))
      .rejects.toMatchObject({ code: '23505' });
  });

  it('RPC mati: draw tetap sukses, jangkar failed dengan backoff, lalu dicoba ulang dan berhasil', async () => {
    await start();
    rpc.down = true;
    const gid = (await mkGiveaway(api, adm)).giveaway_id;
    const codes = await genCodes(api, adm, gid, 1);
    await register(api, 'peserta1', 'p1@example.test', 'Peserta1!', 'Peserta');
    const user = (await login(api, 'peserta1', 'Peserta1!')).token;
    expect((await redeem(api, user, codes[0])).ok).toBe(true); // redeem tidak menunggu jangkar
    const d = await executeDraw(real.pool, gid, 'admin_demo');
    expect(d).toMatchObject({ ok: true, status: 'completed', total_tickets: 1 });
    await settle();
    let row = await rowOf(gid, 'result');
    expect(row).toMatchObject({ status: 'failed', attempts: 1, tx_hash: null });
    const wait = (await real.su.query('select extract(epoch from next_attempt_at - now())::float8 as s from chain_anchors where id = $1', [row.id])).rows[0].s;
    expect(wait).toBeGreaterThan(20);
    expect(wait).toBeLessThanOrEqual(backoffSeconds(1));
    expect(backoffSeconds(2)).toBe(60);
    expect(backoffSeconds(20)).toBe(3600);

    const before = rpc.calls.length;
    await anchor.runOnce(); // belum jatuh tempo: tidak ada panggilan RPC
    expect(rpc.calls.length).toBe(before);

    rpc.down = false;
    await real.su.query('update chain_anchors set next_attempt_at = now()');
    await anchor.runOnce();
    row = await rowOf(gid, 'result');
    expect(row).toMatchObject({ status: 'pending', attempts: 2, last_error: null });
    expect(row.tx_hash).toMatch(/^0x[0-9a-f]{64}$/);
  });

  it(`maksimum ${MAX_ATTEMPTS} percobaan: setelah habis tidak dicoba lagi`, async () => {
    await start();
    rpc.down = true;
    const gid = (await mkGiveaway(api, adm)).giveaway_id;
    await settle();
    const row = await rowOf(gid, 'commit');
    await real.su.query('update chain_anchors set attempts = $2, next_attempt_at = now() where id = $1', [row.id, MAX_ATTEMPTS - 1]);
    await anchor.runOnce();
    expect(await rowOf(gid, 'commit')).toMatchObject({ status: 'failed', attempts: MAX_ATTEMPTS });
    rpc.down = false;
    await real.su.query('update chain_anchors set next_attempt_at = now() where id = $1', [row.id]);
    const sent = rpc.sent.length;
    await anchor.runOnce();
    expect(rpc.sent.length).toBe(sent);
    expect((await rowOf(gid, 'commit')).status).toBe('failed');
  });

  it('transaksi hilang dari mempool (nonce terpakai atau terlalu lama): hash dihapus lalu dikirim ulang sekali', async () => {
    await start();
    rpc.drop = true; // node menerima tetapi membuang transaksi
    const gid = (await mkGiveaway(api, adm)).giveaway_id;
    await settle();
    const first = await rowOf(gid, 'commit');
    expect(first.tx_hash).not.toBeNull();
    await real.su.query('update chain_anchors set next_attempt_at = now() where id = $1', [first.id]);
    await anchor.runOnce(); // baru dikirim, nonce belum terpakai: tunggu, jangan kirim ulang
    expect((await rowOf(gid, 'commit')).tx_hash).toBe(first.tx_hash);

    rpc.drop = false;
    await real.su.query("update chain_anchors set next_attempt_at = now(), anchored_at = now() - interval '10 minutes' where id = $1", [first.id]);
    await anchor.runOnce();
    const reset = await rowOf(gid, 'commit');
    expect(reset).toMatchObject({ tx_hash: null, status: 'pending', last_error: 'transaksi hilang dari mempool' });
    await real.su.query('update chain_anchors set next_attempt_at = now() where id = $1', [first.id]);
    await anchor.runOnce();
    const again = await rowOf(gid, 'commit');
    expect(again).toMatchObject({ status: 'pending', attempts: 2 });
    // Nonce yang sama dipakai lagi, jadi paling banyak satu dari keduanya bisa ditambang (tidak ada jangkar ganda).
    expect(rpc.sent.map((x) => x.tx.nonce)).toEqual([0, 0]);
    expect(rpc.txs.has(again.tx_hash)).toBe(true);
  });

  it('kunci privat dan key RPC tidak pernah muncul di log, last_error, atau respons API', async () => {
    await start();
    rpc.down = true;
    const gid = (await mkGiveaway(api, adm)).giveaway_id;
    await settle();
    await executeDraw(real.pool, gid, 'admin_demo');
    await settle();
    // Galat RPC asli memuat URL ber-key: harus tersensor.
    const all = [
      logs.join('\n'),
      JSON.stringify(await rows()),
      JSON.stringify(await api.get(`/giveaways/${gid}/anchors`)),
      JSON.stringify(await api.get(`/giveaways/${gid}/verification`)),
    ].join('\n');
    expect(logs.length).toBeGreaterThan(0);
    for (const secret of [KEY, KEY.slice(2), RPC_KEY, RPC_URL]) expect(all.toLowerCase()).not.toContain(secret.toLowerCase());
    expect((await rowOf(gid, 'commit')).last_error).toBeTruthy();
    const s = anchorSettings(env());
    expect(redact(`gagal ${KEY} ${KEY.slice(2).toUpperCase()} di ${RPC_URL}?x=1`, s)).toBe('gagal [kunci] [kunci] di [rpc]');
  });

  it('migrasi 12 belum dijalankan: giveaway dan draw tetap sukses, API menjawab "none"', async () => {
    const old = {};
    const oldApi = makeApi(() => old.app);
    const token = await setup(old, oldApi, 'anchor_old', MIGRATIONS_BEFORE_12);
    try {
      logs = [];
      rpc = mockRpc();
      anchor = startAnchor({ pool: old.pool, config: env(), log: (l) => logs.push(l), intervalMs: 0,
        client: viemClient({ ...anchorSettings(env()), fetchFn: rpc.fetchFn, retryCount: 0 }) });
      const gid = (await mkGiveaway(oldApi, token)).giveaway_id;
      expect(gid).toBeTruthy();
      expect((await executeDraw(old.pool, gid, 'admin_demo')).ok).toBe(true);
      await anchor.runOnce();
      expect(rpc.sent).toHaveLength(0);
      const r = await oldApi.get(`/giveaways/${gid}/anchors`);
      expect(r.anchors.map((a) => a.status)).toEqual(['none', 'none']);
      expect(logs.join('\n')).toContain('12_chain_anchors.sql');
    } finally {
      stopAnchor();
      await old.close();
    }
  });

  it('GET /giveaways/:id/anchors: id bukan UUID -> invalid_input, tidak ada -> not_found (HTTP 200)', async () => {
    const bad = await api.raw('get', '/giveaways/abc/anchors');
    expect(bad.status).toBe(200);
    expect(bad.body).toMatchObject({ ok: false, error: 'invalid_input' });
    const none = await api.raw('get', '/giveaways/00000000-0000-4000-8000-000000000000/anchors');
    expect(none.status).toBe(200);
    expect(none.body).toEqual({ ok: false, error: 'not_found' });
  });
});
