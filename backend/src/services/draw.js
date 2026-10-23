import { withTx } from '../db.js';
import { ownerKey, pickWinners, appendBlock } from '../lib/chain.js';
import { fail, ok, sha256Hex } from '../lib/util.js';
import { notify } from './users.js';
import { kickAnchor, queueAnchor } from './anchor.js';

const pad6 = (n) => String(n).padStart(6, '0');

// Satu transaksi per draw. Hasil gagal-bisnis (already_drawn, seed_mismatch, ...) dikembalikan dan di-commit
// supaya system_events tetap tercatat; hanya exception yang me-rollback seluruh draw.
// Jangkar blockchain dikirim setelah commit, tanpa ditunggu.
export async function executeDraw(pool, giveawayId, trigger) {
  const out = await withTx(pool, (c) => drawInTx(c, giveawayId, trigger));
  if (out.ok) kickAnchor();
  return out;
}

// Pemilihan pemenang commit-reveal. Aturan: hash-chain commit-reveal.
async function drawInTx(c, giveawayId, trigger) {
  // Mengunci baris giveaway; redeem mengunci baris yang sama, jadi kumpulan tiket tidak berubah selama draw.
  const g = (
    await c.query(
      `select g.*, now() < g.draw_at as before_draw, now() < g.start_at as before_start
         from giveaways g where g.id = $1 for update`,
      [giveawayId],
    )
  ).rows[0];
  if (!g) return fail('not_found');
  if (g.status === 'drawn' || (await c.query('select 1 from draws where giveaway_id = $1', [g.id])).rowCount > 0) {
    return fail('already_drawn');
  }
  if (trigger === 'scheduler' && g.before_draw) return fail('not_due');
  if (trigger === 'admin_demo' && g.before_start) return fail('not_started');

  // Seed harus cocok dengan commitment di hash-chain
  const seed = (await c.query('select seed from giveaway_secrets where giveaway_id = $1', [g.id])).rows[0]?.seed;
  const commit = (await c.query("select seed_hash from draw_chain where giveaway_id = $1 and block_type = 'commit'", [g.id])).rows[0];
  if (!seed || !commit || sha256Hex(seed) !== commit.seed_hash || commit.seed_hash !== g.seed_hash) {
    await c.query("insert into system_events(level, event, details) values ('error', 'draw_seed_mismatch', $1::jsonb)", [
      JSON.stringify({ giveaway_id: g.id, trigger }),
    ]);
    return fail('seed_mismatch');
  }

  const tk = (await c.query('select id, ticket_number, user_id from tickets where giveaway_id = $1 order by ticket_number', [g.id])).rows;
  const byNumber = new Map(tk.map((t) => [t.ticket_number, t]));
  const tickets = tk.map((t) => [t.ticket_number, ownerKey(t.user_id, g.id)]);
  const total = tickets.length;
  const { ticketsHash, winners } = pickWinners(seed, g.id, tickets, g.winner_count);

  const status = total === 0 ? 'no_participants' : 'completed';
  const draw = (
    await c.query('insert into draws(giveaway_id, total_tickets, trigger_type, status) values ($1,$2,$3,$4) returning id', [
      g.id, total, trigger, status,
    ])
  ).rows[0];

  for (let i = 0; i < winners.length; i++) {
    const t = byNumber.get(winners[i]);
    await c.query('insert into winners(draw_id, giveaway_id, ticket_id, user_id, rank) values ($1,$2,$3,$4,$5)', [
      draw.id, g.id, t.id, t.user_id, i + 1,
    ]);
  }

  const block = await appendBlock(c, {
    block_type: 'result', giveaway_id: g.id, draw_id: draw.id, seed, total_tickets: total,
    tickets_hash: ticketsHash, winning_tickets: winners.join(','),
  });
  await queueAnchor(c, block);
  await c.query("update giveaways set status = 'drawn' where id = $1", [g.id]);

  // Notifikasi: pemenang, lalu peserta lain
  for (const n of winners) {
    const t = byNumber.get(n);
    await notify(c, t.user_id, 'winner', 'Selamat, kamu menang!', `Tiket #${pad6(n)} memenangkan ${g.prize_name} pada undian ${g.title}.`, g.id);
  }
  await c.query(
    `insert into notifications(user_id, type, title, body, giveaway_id)
     select distinct t.user_id, 'draw_result', 'Hasil undian sudah keluar', $2::text, $1::uuid
       from tickets t
      where t.giveaway_id = $1
        and not exists (select 1 from winners w where w.draw_id = $3 and w.user_id = t.user_id)`,
    [g.id, `Undian ${g.title} sudah diundi. Cek hasil tiketmu dan verifikasi hasilnya.`, draw.id],
  );

  await c.query("insert into system_events(level, event, details) values ('info', 'draw_completed', $1::jsonb)", [
    JSON.stringify({ giveaway_id: g.id, trigger, total_tickets: total, winning_tickets: winners, block_index: block.block_index }),
  ]);

  return ok({ draw_id: draw.id, status, total_tickets: total, winning_tickets: winners, block_index: block.block_index });
}

// Mode demo: draw yang sama dengan scheduler, hanya bila flag aktif.
export async function adminRunDraw(pool, giveawayId) {
  const flag = (await pool.query("select value from app_config where key = 'demo_draw_enabled'")).rows[0]?.value ?? 'false';
  if (flag !== 'true') return fail('demo_disabled');
  return executeDraw(pool, giveawayId, 'admin_demo');
}

// Dipanggil node-cron tiap menit dan POST /internal/tick. Mengembalikan jumlah draw yang berhasil.
export async function runDueDraws(pool) {
  await refreshGiveawayStatus(pool);
  const due = (
    // Giveaway yang pernah gagal seed_mismatch dilewati: seed tidak akan membaik sendiri, jadi mengulang tiap menit hanya
    // memenuhi system_events. Dicatat sekali oleh drawInTx; operator membukanya lagi dengan menghapus event itu
    // setelah seed diperbaiki (lihat README). Draw manual admin tetap bisa dicoba.
    await pool.query(
      `select g.id from giveaways g
        where g.status <> 'drawn' and g.draw_at <= now()
          and not exists (select 1 from system_events e where e.event = 'draw_seed_mismatch' and e.details->>'giveaway_id' = g.id::text)
        order by g.draw_at`,
    )
  ).rows;
  let done = 0;
  for (const { id } of due) {
    try {
      const r = await executeDraw(pool, id, 'scheduler');
      if (r.ok) done += 1;
    } catch (e) {
      await pool
        .query("insert into system_events(level, event, details) values ('error', 'draw_exception', $1::jsonb)", [
          JSON.stringify({ giveaway_id: id, message: String(e.message).slice(0, 500) }),
        ])
        .catch(() => {});
    }
  }
  return done;
}

export async function refreshGiveawayStatus(pool) {
  const r = await pool.query(
    `update giveaways
        set status = case when now() < start_at then 'upcoming' when now() < end_at then 'active' else 'waiting_draw' end
      where status <> 'drawn'
        and status <> case when now() < start_at then 'upcoming' when now() < end_at then 'active' else 'waiting_draw' end`,
  );
  return r.rowCount;
}

// Percobaan login/redeem lama dibuang. Kunci yang masih aktif dan percobaan < 24 jam tidak disentuh (aturan lockout tetap).
export async function cleanupAttempts(pool) {
  await pool.query("delete from code_attempts where attempted_at < now() - interval '1 day'");
  await pool.query(
    "delete from login_attempts where last_attempt_at < now() - interval '24 hours' and (locked_until is null or locked_until < now())",
  );
}

// Dijalankan tiap jam oleh scheduler dan, karena Render gratis bisa tertidur sehingga cron internal tidak jalan,
// juga dari /internal/tick (dibatasi sekali per jam per proses). Tanpa ini login_attempts bisa tumbuh dengan identifier acak.
let lastMaintenance = 0;
export async function runMaintenance(pool, { force = false, now = Date.now() } = {}) {
  if (!force && now - lastMaintenance < 3_600_000) return false;
  lastMaintenance = now;
  await cleanupAttempts(pool);
  return true;
}

export async function cleanup(pool) {
  await pool.query(
    "delete from sessions where expires_at < now() - interval '30 days' or (not is_valid and created_at < now() - interval '30 days')",
  );
  await cleanupAttempts(pool);
}
