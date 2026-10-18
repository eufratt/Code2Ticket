import { sha256Hex } from './util.js';

export const GENESIS_HASH = '0'.repeat(64);

// Kontrak hashing (aturan hash-chain commit-reveal). Jangan diubah.
export function blockHashInput(b) {
  return b.block_type === 'commit'
    ? `C|${b.block_index}|${b.giveaway_id}|${b.seed_hash}|${b.winner_count}|${b.ts_ms}|${b.previous_hash}`
    : `R|${b.block_index}|${b.giveaway_id}|${b.draw_id}|${b.seed}|${b.total_tickets}|` +
        `${b.tickets_hash}|${b.winning_tickets}|${b.ts_ms}|${b.previous_hash}`;
}
export const blockHash = (b) => sha256Hex(blockHashInput(b));

// Kontrak pemilihan pemenang. tickets = [[nomor, owner_key], ...] terurut naik.
// 7 byte pertama = 56 bit -> BigInt (di atas 2^53).
export function ticketsHash(tickets) {
  return sha256Hex(tickets.map(([n, o]) => `${n}:${o}`).join(','));
}

export function pickWinners(seed, giveawayId, tickets, winnerCount) {
  const th = ticketsHash(tickets);
  let pool = tickets;
  const winners = [];
  for (let j = 0; winners.length < winnerCount && pool.length > 0; j++) {
    const h = sha256Hex(`${seed}:${giveawayId}:${th}:${j}`);
    const idx = Number(BigInt('0x' + h.slice(0, 14)) % BigInt(pool.length));
    const [n, o] = pool[idx];
    winners.push(n);
    pool = pool.filter((t) => t[1] !== o);
  }
  return { ticketsHash: th, winners };
}

export const ownerKey = (userId, giveawayId) => sha256Hex(`${userId}:${giveawayId}`).slice(0, 12);

// Menambah block. Dipanggil di dalam transaksi; advisory lock menjaga block_index dan
// previous_hash tetap berurutan. ts_ms memakai jam database (clock_timestamp).
export async function appendBlock(client, b) {
  await client.query('select pg_advisory_xact_lock(7340001)');
  const last = (await client.query('select block_index, block_hash from draw_chain order by block_index desc limit 1')).rows[0];
  const ts = (await client.query('select floor(extract(epoch from clock_timestamp()) * 1000)::bigint as ts')).rows[0].ts;
  const block = {
    seed_hash: null, seed: null, winner_count: null, total_tickets: null, tickets_hash: null,
    winning_tickets: null, draw_id: null, ...b,
    block_index: (last?.block_index ?? 0) + 1,
    ts_ms: ts,
    previous_hash: last?.block_hash ?? GENESIS_HASH,
  };
  block.block_hash = blockHash(block);
  await client.query(
    `insert into draw_chain(block_index, block_type, giveaway_id, draw_id, seed_hash, seed, winner_count,
       total_tickets, tickets_hash, winning_tickets, ts_ms, previous_hash, block_hash)
     values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)`,
    [block.block_index, block.block_type, block.giveaway_id, block.draw_id, block.seed_hash, block.seed,
      block.winner_count, block.total_tickets, block.tickets_hash, block.winning_tickets, block.ts_ms,
      block.previous_hash, block.block_hash],
  );
  return block;
}

// Audit rantai di sisi server (pengganti fn_verify_chain).
export async function verifyChain(db) {
  const rows = (await db.query('select * from draw_chain order by block_index')).rows;
  let prev = GENESIS_HASH;
  return rows.map((b) => {
    let okk = true;
    let reason = null;
    if (b.previous_hash !== prev) { okk = false; reason = 'previous_hash tidak cocok'; }
    else if (b.block_hash !== blockHash(b)) { okk = false; reason = 'block_hash tidak cocok'; }
    prev = b.block_hash;
    return { block_index: b.block_index, ok: okk, reason };
  });
}
