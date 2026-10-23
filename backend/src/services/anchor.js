import { createPublicClient, defineChain, http, keccak256, toHex } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { fail, ok } from '../lib/util.js';

// Jangkar hash blok draw_chain ke blockchain publik (testnet): transaksi value 0 ke alamat dompet sendiri dengan
// data = hex("C2T:" + block_hash). Tanpa smart contract. Jangkar hanya bukti tambahan: kegagalannya tidak pernah
// menggagalkan pembuatan giveaway, draw, atau redeem. Kunci privat dan URL RPC (bisa memuat API key) tidak pernah
// masuk log, respons, atau last_error (lihat redact).

export const MAX_ATTEMPTS = 6;
const BATCH = 20;
const MEMPOOL_WAIT_S = 30; // jeda cek berikutnya selama transaksi belum ditambang
const LOST_AFTER_MS = 5 * 60_000; // transaksi tak dikenal node selama ini = hilang, kirim ulang

// RPC publik tanpa key dan explorer bawaan per chain; env ANCHOR_PUBLIC_RPC_URL / ANCHOR_EXPLORER_TX_URL menimpanya.
const PUBLIC_RPC = { 80002: 'https://rpc-amoy.polygon.technology' };
const EXPLORER_TX = { 80002: 'https://amoy.polygonscan.com/tx/{tx}' };

export const anchorData = (blockHash) => toHex(`C2T:${blockHash}`);

// Backoff percobaan kirim: 30 dtk, 1, 2, 4, ... menit, maks. 1 jam.
export const backoffSeconds = (attempts) => Math.min(30 * 2 ** Math.max(attempts - 1, 0), 3600);

const chainIdOf = (config) => {
  const n = Number(config.ANCHOR_CHAIN_ID || 80002);
  return Number.isInteger(n) && n > 0 ? n : null;
};

// https absolut tanpa kredensial; selain itu null (tidak pernah dikirim ke klien).
function safeHttps(s) {
  try {
    const u = new URL(String(s ?? '').trim());
    return u.protocol === 'https:' && !u.username && !u.password ? u.href : null;
  } catch {
    return null;
  }
}

// Konfigurasi pengirim. null = fitur mati (ANCHOR_ENABLED bukan "true" atau ada nilai yang kurang/tidak valid).
export function anchorSettings(config) {
  if (String(config.ANCHOR_ENABLED ?? '').trim() !== 'true') return null;
  const key = String(config.ANCHOR_PRIVATE_KEY ?? '').trim();
  const rpcUrl = String(config.ANCHOR_RPC_URL ?? '').trim();
  const chainId = chainIdOf(config);
  if (!/^(0x)?[0-9a-fA-F]{64}$/.test(key) || !/^https?:\/\/\S+$/.test(rpcUrl) || !chainId) return null;
  return { chainId, rpcUrl, privateKey: key.startsWith('0x') ? key : `0x${key}` };
}

// URL yang aman ditampilkan ke klien untuk satu chain_id.
export function publicLinks(config, chainId) {
  const same = chainId === chainIdOf(config);
  const rpc = (same && safeHttps(config.ANCHOR_PUBLIC_RPC_URL)) || PUBLIC_RPC[chainId] || null;
  const tpl = (same && String(config.ANCHOR_EXPLORER_TX_URL ?? '').trim()) || EXPLORER_TX[chainId] || '';
  return { rpcUrl: rpc, explorer: (tx) => (tpl.includes('{tx}') ? safeHttps(tpl.replace('{tx}', tx)) : null) };
}

// Membuang kunci privat (dengan/tanpa 0x) dan URL RPC beserta path/query-nya dari teks galat.
export function redact(text, settings) {
  let s = String(text ?? '');
  const esc = (x) => x.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  if (settings) {
    const k = settings.privateKey.slice(2);
    s = s.replace(new RegExp(`(0x)?${esc(k)}`, 'gi'), '[kunci]');
    let origin = settings.rpcUrl;
    try { origin = new URL(settings.rpcUrl).origin; } catch { /* bukan URL: sensor apa adanya */ }
    s = s.replace(new RegExp(`${esc(origin)}[^\\s"'\`)]*`, 'gi'), '[rpc]');
  }
  return s.replace(/\s+/g, ' ').slice(0, 300);
}

// Klien JSON-RPC lewat viem. fetchFn hanya untuk tes (RPC tiruan).
export function viemClient({ rpcUrl, chainId, privateKey, fetchFn, retryCount = 1, timeout = 15_000 }) {
  const account = privateKeyToAccount(privateKey);
  const chain = defineChain({
    id: chainId, name: `chain-${chainId}`, nativeCurrency: { name: 'POL', symbol: 'POL', decimals: 18 },
    rpcUrls: { default: { http: [rpcUrl] } },
  });
  const rpc = createPublicClient({ chain, transport: http(rpcUrl, { fetchFn, retryCount, timeout }) });
  const call = (method, params) => rpc.request({ method, params });
  return {
    async sign(data) {
      const req = await rpc.prepareTransactionRequest({ account, to: account.address, value: 0n, data, chain });
      const raw = await account.signTransaction(req);
      return { raw, hash: keccak256(raw), nonce: req.nonce };
    },
    broadcast: (raw) => call('eth_sendRawTransaction', [raw]),
    receipt: (hash) => call('eth_getTransactionReceipt', [hash]),
    transaction: (hash) => call('eth_getTransactionByHash', [hash]),
    latestNonce: () => rpc.getTransactionCount({ address: account.address, blockTag: 'latest' }),
  };
}

let active = null;

// Menyalakan pengirim jangkar (satu per proses). null bila fitur mati; tidak pernah melempar karena konfigurasi.
export function startAnchor({ pool, config, log = () => {}, client, intervalMs = 60_000, now = Date.now }) {
  stopAnchor();
  const s = anchorSettings(config);
  if (!s) {
    if (String(config.ANCHOR_ENABLED ?? '').trim() === 'true') log('anchor: konfigurasi tidak lengkap, fitur dimatikan');
    return null;
  }
  let rpc;
  try {
    rpc = client ?? viemClient(s);
  } catch {
    log('anchor: kunci tidak valid, fitur dimatikan');
    return null;
  }
  const say = (msg, e) => log(`anchor: ${msg}${e ? ` (${redact(e.shortMessage ?? e.message ?? e.code ?? e.name, s)})` : ''}`);
  const q = (sql, params) => pool.query(sql, params);

  async function failSend(row, e) {
    const attempts = row.attempts + 1;
    await q(
      `update chain_anchors set attempts = $2, status = 'failed', last_error = $3,
              next_attempt_at = now() + make_interval(secs => $4) where id = $1 and tx_hash is null and status <> 'confirmed'`,
      [row.id, attempts, redact(e.shortMessage ?? e.message ?? e.name, s), backoffSeconds(attempts)],
    );
    say(`kirim blok ${row.chain_block_id} gagal, percobaan ${attempts}/${MAX_ATTEMPTS}`, e);
  }

  async function send(row) {
    let signed;
    try {
      signed = await rpc.sign(anchorData(row.block_hash));
    } catch (e) {
      return failSend(row, e);
    }
    // Hash transaksi disimpan SEBELUM disiarkan, dan hanya satu pekerja yang menang (tx_hash is null): tidak ada
    // dua transaksi untuk blok yang sama; bila proses mati setelah siaran, cek berikutnya memakai hash ini.
    const won = await q(
      `update chain_anchors set tx_hash = $2, nonce = $3, attempts = attempts + 1, status = 'pending', last_error = null,
              anchored_at = now(), next_attempt_at = now() + make_interval(secs => $4)
        where id = $1 and tx_hash is null and status <> 'confirmed' returning attempts`,
      [row.id, signed.hash, signed.nonce, MEMPOOL_WAIT_S],
    );
    if (!won.rowCount) return;
    try {
      await rpc.broadcast(signed.raw);
    } catch (e) {
      // Bisa jadi sudah masuk mempool ("already known"); cek() yang memutuskan apakah perlu kirim ulang.
      const attempts = won.rows[0].attempts;
      await q(
        `update chain_anchors set status = 'failed', last_error = $3, next_attempt_at = now() + make_interval(secs => $4)
          where id = $1 and tx_hash = $2`,
        [row.id, signed.hash, redact(e.shortMessage ?? e.message ?? e.name, s), backoffSeconds(attempts)],
      );
      say(`siaran blok ${row.chain_block_id} gagal`, e);
    }
  }

  async function check(row) {
    const later = (secs, error = null) =>
      q(
        `update chain_anchors set next_attempt_at = now() + make_interval(secs => $3), last_error = coalesce($4, last_error)
          where id = $1 and tx_hash = $2`,
        [row.id, row.tx_hash, secs, error],
      );
    try {
      const receipt = await rpc.receipt(row.tx_hash);
      if (receipt?.status === '0x1') {
        await q(
          `update chain_anchors set status = 'confirmed', confirmed_at = now(), last_error = null where id = $1 and tx_hash = $2`,
          [row.id, row.tx_hash],
        );
        return;
      }
      if (receipt) return reset(row, 'transaksi gagal (revert)');
      if (await rpc.transaction(row.tx_hash)) return later(MEMPOOL_WAIT_S); // masih di mempool
      // Tak dikenal node. Hilang bila nonce-nya sudah dipakai transaksi lain (tidak mungkin ditambang lagi) atau sudah
      // terlalu lama. Kirim ulang memakai nonce pending: bila nonce lama belum terpakai, transaksi baru menggantikannya.
      const age = now() - new Date(row.anchored_at ?? 0).getTime();
      const consumed = row.nonce != null && Number(await rpc.latestNonce()) > Number(row.nonce);
      if (consumed || age >= LOST_AFTER_MS) return reset(row, 'transaksi hilang dari mempool');
      return later(MEMPOOL_WAIT_S);
    } catch (e) {
      say(`cek blok ${row.chain_block_id} gagal`, e);
      return later(backoffSeconds(row.attempts), redact(e.shortMessage ?? e.message ?? e.name, s));
    }
  }

  async function reset(row, reason) {
    const giveUp = row.attempts >= MAX_ATTEMPTS;
    await q(
      `update chain_anchors set tx_hash = null, nonce = null, status = $3, last_error = $4,
              next_attempt_at = now() + make_interval(secs => $5) where id = $1 and tx_hash = $2`,
      [row.id, row.tx_hash, giveUp ? 'failed' : 'pending', reason, giveUp ? 0 : backoffSeconds(row.attempts)],
    );
    say(`blok ${row.chain_block_id}: ${reason}`);
  }

  let running = null;
  // Satu putaran: blok yang jatuh tempo (belum confirmed, belum habis percobaan). Tidak pernah melempar.
  function runOnce() {
    running ??= (async () => {
      const rows = (
        await q(
          `select * from chain_anchors where status <> 'confirmed' and next_attempt_at <= now()
              and (tx_hash is not null or attempts < $1) order by id limit $2`,
          [MAX_ATTEMPTS, BATCH],
        )
      ).rows;
      for (const row of rows) {
        await (row.tx_hash ? check(row) : send(row)).catch((e) => say(`blok ${row.chain_block_id} galat`, e));
      }
    })()
      .catch((e) => say(e.code === '42P01' ? 'tabel chain_anchors belum ada (jalankan db/12_chain_anchors.sql)' : 'putaran gagal', e.code === '42P01' ? null : e))
      .finally(() => { running = null; });
    return running;
  }

  const timer = intervalMs > 0 ? setInterval(runOnce, intervalMs) : null;
  timer?.unref?.();
  active = { chainId: s.chainId, runOnce, log: say, stop: () => timer && clearInterval(timer) };
  log(`anchor: aktif (chain ${s.chainId})`);
  return active;
}

export function stopAnchor() {
  active?.stop();
  active = null;
}

// Dipanggil di DALAM transaksi pembuatan blok. Savepoint: bila tabel belum ada atau insert gagal, transaksi
// giveaway/draw tetap jalan. Fitur mati = tidak ada baris (klien menampilkan "Belum dijangkarkan").
export async function queueAnchor(c, block) {
  if (!active) return;
  try {
    await c.query('savepoint chain_anchor');
    await c.query(
      `insert into chain_anchors(chain_block_id, block_hash, chain_id)
       select id, block_hash, $2 from draw_chain where block_index = $1
       on conflict (chain_block_id) do nothing`,
      [block.block_index, active.chainId],
    );
    await c.query('release savepoint chain_anchor');
  } catch (e) {
    await c.query('rollback to savepoint chain_anchor');
    active.log(`blok ${block.block_index} tidak diantrekan (${e.code ?? e.name})`);
  }
}

// Setelah transaksi commit: kirim secepatnya tanpa ditunggu. Yang terlewat diambil putaran berkala.
export function kickAnchor() {
  const a = active;
  if (a) setImmediate(() => a.runOnce());
}

// GET /giveaways/:id/anchors (publik). Satu entri per blok giveaway; status 'none' = belum dijangkarkan.
export async function getAnchors(pool, config, giveawayId) {
  const g = (await pool.query('select id from giveaways where id = $1', [giveawayId])).rows[0];
  if (!g) return fail('not_found');
  const base = 'from draw_chain d where d.giveaway_id = $1 order by d.block_index';
  let rows;
  try {
    rows = (
      await pool.query(
        `select d.block_index, d.block_type, d.block_hash, a.tx_hash, a.chain_id, a.status
           from draw_chain d left join chain_anchors a on a.chain_block_id = d.id
          where d.giveaway_id = $1 order by d.block_index`,
        [g.id],
      )
    ).rows;
  } catch (e) {
    if (e.code !== '42P01') throw e; // migrasi 12 belum dijalankan
    rows = (await pool.query(`select d.block_index, d.block_type, d.block_hash ${base}`, [g.id])).rows;
  }
  return ok({
    anchors: rows.map((r) => {
      const links = r.chain_id ? publicLinks(config, r.chain_id) : null;
      return {
        block_index: r.block_index,
        block_type: r.block_type,
        block_hash: r.block_hash,
        tx_hash: r.tx_hash ?? null,
        chain_id: r.chain_id ?? null,
        status: r.status ?? 'none',
        explorer_url: r.tx_hash && links ? links.explorer(r.tx_hash) : null,
        rpc_url: links?.rpcUrl ?? null,
      };
    }),
  });
}
