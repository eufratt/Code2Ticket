import { z } from 'zod';
import { withTx } from '../db.js';
import { distanceKm } from '../lib/geo.js';
import { fail, ok, parseInput } from '../lib/util.js';
import { effectiveStatus } from '../lib/sql.js';
import { awardBadges, notify } from './users.js';

const MAX_FAILS = 5;
// Hanya tebakan kode yang dihitung ke batas: format salah, kode tak dikenal, atau kode yang sudah dipakai ORANG LAIN.
// Alasan sah (belum mulai, berakhir, di luar area, batas tiket, kode sendiri) tetap dicatat tetapi tidak menghitung.
const GUESS_REASONS = ['invalid_format', 'code_not_found', 'code_used'];

const redeemSchema = z.object({
  // Bukan string / terlalu panjang diperlakukan seperti kode kosong: invalid_format dan tercatat sebagai kegagalan.
  code: z.string().max(200).catch(''),
  lat: z.number().min(-90).max(90).nullish(),
  lng: z.number().min(-180).max(180).nullish(),
});

// Satu transaksi: kunci baris kode lalu giveaway (urutan sama dengan SQL lama, menghindari deadlock).
// Kegagalan bisnis dikembalikan (bukan dilempar) sehingga catatan code_attempts tetap di-commit.
export async function redeemCode(pool, user, body) {
  const p = parseInput(redeemSchema, body);
  if (p.error) return p.error;
  const { code, lat, lng } = p.data;

  return withTx(pool, async (c) => {
    // [stored] = alasan di code_attempts bila berbeda dari kode galat untuk klien.
    const failCode = async (reason, stored = reason) => {
      await c.query('insert into code_attempts(user_id, success, reason) values ($1, false, $2)', [user.id, stored]);
      return fail(reason);
    };

    // Pembatasan: maks. 5 kegagalan per 10 menit per pengguna
    const recent = (
      await c.query(
        `select count(*)::int as n from code_attempts
          where user_id = $1 and not success and reason = any($2) and attempted_at > now() - interval '10 minutes'`,
        [user.id, GUESS_REASONS],
      )
    ).rows[0].n;
    if (recent >= MAX_FAILS) {
      const r = (
        await c.query(
          `select greatest(1, ceil(extract(epoch from (attempted_at + interval '10 minutes' - now())))::int) as retry
             from code_attempts
            where user_id = $1 and not success and reason = any($2) and attempted_at > now() - interval '10 minutes'
            order by attempted_at desc offset 4 limit 1`,
          [user.id, GUESS_REASONS],
        )
      ).rows[0];
      return fail('rate_limited', { retry_after_seconds: r.retry });
    }

    const stripped = code.replace(/[\s-]/g, '');
    if (!/^[A-Za-z0-9]{12}$/.test(stripped)) return failCode('invalid_format');
    const norm = stripped.toUpperCase();
    const formatted = `${norm.slice(0, 4)}-${norm.slice(4, 8)}-${norm.slice(8, 12)}`;

    const cd = (await c.query('select * from codes where code = $1 for update', [formatted])).rows[0];
    if (!cd) return failCode('code_not_found');
    const g = (
      await c.query(
        `select g.*, now() >= g.end_at as ended, now() < g.start_at as not_started,
                now() < g.start_at + interval '24 hours' as early
           from giveaways g where g.id = $1 for update`,
        [cd.giveaway_id],
      )
    ).rows[0];

    if (cd.is_used) return cd.used_by === user.id ? failCode('code_used', 'code_used_self') : failCode('code_used');
    if (g.status === 'drawn' || g.ended) return failCode('giveaway_ended');
    if (g.not_started) return failCode('giveaway_not_started');
    const hasCommit = (await c.query("select 1 from draw_chain where giveaway_id = $1 and block_type = 'commit'", [g.id])).rowCount > 0;
    if (!hasCommit) return failCode('giveaway_not_ready'); // commit block wajib ada sebelum tiket

    const mine = (await c.query('select count(*)::int as n from tickets where giveaway_id = $1 and user_id = $2', [g.id, user.id])).rows[0].n;
    if (mine >= g.max_tickets_per_user) return failCode('ticket_limit');

    if (cd.geo_radius_km !== null) {
      if (lat == null || lng == null) return failCode('location_required');
      if (distanceKm(cd.geo_lat, cd.geo_lng, lat, lng) > cd.geo_radius_km) return failCode('out_of_area');
    }

    const num = g.ticket_counter + 1;
    await c.query('update giveaways set ticket_counter = $2 where id = $1', [g.id, num]);
    const t = (
      await c.query(
        'insert into tickets(giveaway_id, ticket_number, user_id, code_id) values ($1,$2,$3,$4) returning id',
        [g.id, num, user.id, cd.id],
      )
    ).rows[0];
    await c.query('update codes set is_used = true, used_by = $2, used_at = now() where id = $1', [cd.id, user.id]);

    await c.query('insert into code_attempts(user_id, success) values ($1, true)', [user.id]);
    await c.query("insert into user_activity(user_id, activity_type, giveaway_id, category) values ($1, 'ticket_created', $2, $3)", [
      user.id, g.id, g.category,
    ]);
    await notify(c, user.id, 'ticket_created', 'Tiket berhasil dibuat', `Tiket #${String(num).padStart(6, '0')} untuk ${g.title}.`, g.id);
    await awardBadges(c, user.id, g.early);

    return ok({
      ticket: {
        id: t.id, ticket_number: num, giveaway_id: g.id, giveaway_title: g.title, prize_name: g.prize_name,
        draw_at: g.draw_at, result: 'eligible',
      },
    });
  });
}

export async function getMyTickets(pool, user) {
  const r = await pool.query(
    `select t.id, t.ticket_number, t.giveaway_id, g.title as giveaway_title, g.prize_name,
            g.category, g.end_at, g.draw_at, ${effectiveStatus('g')} as giveaway_status, t.created_at,
            case when g.status = 'drawn' then (case when w.id is not null then 'winner' else 'not_selected' end)
                 when now() >= g.end_at then 'waiting_for_draw'
                 else 'eligible' end as result,
            '****-****-' || right(c.code, 4) as code_masked
       from tickets t
       join giveaways g on g.id = t.giveaway_id
       join codes c on c.id = t.code_id
       left join winners w on w.ticket_id = t.id
      where t.user_id = $1
      order by t.created_at desc, t.ticket_number desc`,
    [user.id],
  );
  return r.rows;
}
