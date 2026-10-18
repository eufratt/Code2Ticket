import { z } from 'zod';
import { fail, ok, parseInput, pgTrim } from '../lib/util.js';
import { maskName } from '../lib/geo.js';
import { ownerKey } from '../lib/chain.js';

const blank = (v) => (v === '' || v == null ? undefined : v);
const num = z.preprocess(blank, z.coerce.number().finite().optional());
const int = z.preprocess(blank, z.coerce.number().int().optional());
const txt = z.preprocess(blank, z.string().optional());

const searchSchema = z.object({
  q: txt, category: txt, min_value: num, max_value: num, lat: num, lng: num, radius_km: num,
  deadline_days: int, status: txt, sort: txt, limit: int, offset: int,
});

export const uuidSchema = z.uuid();

// Pencarian publik (Discover). Filter, radius, dan urutan dilakukan di database.
export async function searchGiveaways(pool, query) {
  const p = parseInput(searchSchema, query);
  if (p.error) return p.error;
  const a = p.data;
  let q = a.q == null ? null : pgTrim(a.q) || null;
  if (q !== null) q = '%' + q.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_') + '%';
  const limit = Math.min(Math.max(a.limit ?? 20, 1), 50);
  const offset = Math.max(a.offset ?? 0, 0);

  const r = await pool.query(
    `with base as (
       select g.id, g.title, g.description, g.organizer, g.category, g.prize_name, g.prize_value_usd,
              g.latitude, g.longitude, g.address, g.radius_km, g.start_at, g.end_at, g.draw_at,
              g.winner_count, g.ticket_counter as ticket_count, g.status,
              case when $5::float8 is not null and $6::float8 is not null and g.latitude is not null
                   then round((2 * 6371.0 * asin(sqrt(least(1.0,
                          power(sin(radians(g.latitude - $5::float8) / 2), 2)
                          + cos(radians($5::float8)) * cos(radians(g.latitude))
                            * power(sin(radians(g.longitude - $6::float8) / 2), 2)))))::numeric, 2) end as distance_km
         from giveaways g
        where ($1::text is null or g.title ilike $1 escape '\\' or g.prize_name ilike $1 escape '\\' or g.organizer ilike $1 escape '\\')
          and ($2::text is null or g.category = $2)
          and ($3::numeric is null or g.prize_value_usd >= $3)
          and ($4::numeric is null or g.prize_value_usd <= $4)
          and ($8::int is null or g.end_at <= now() + make_interval(days => $8::int))
          and case coalesce($9::text, 'active')
                when 'active'   then g.status <> 'drawn' and now() >= g.start_at and now() < g.end_at
                when 'upcoming' then g.status <> 'drawn' and now() < g.start_at
                when 'finished' then g.status = 'drawn' or now() >= g.end_at
                else true end
     ), filtered as (
       select * from base
        where $7::numeric is null or (distance_km is not null and distance_km <= $7::numeric)
     ), ranked as (
       select f.*, row_number() over (
                order by (case when $10::text = 'nearest' then f.distance_km end) asc nulls last,
                         (case when $10::text = 'value'   then f.prize_value_usd end) desc nulls last,
                         (case when $10::text = 'newest'  then f.start_at end) desc nulls last,
                         f.end_at asc, f.id) as rn
         from filtered f
     )
     select id, title, description, organizer, category, prize_name, prize_value_usd, latitude, longitude, address,
            radius_km, start_at, end_at, draw_at, winner_count, ticket_count, status, distance_km
       from ranked where rn > $12::int and rn <= $12::int + $11::int order by rn`,
    [q, a.category ?? null, a.min_value ?? null, a.max_value ?? null, a.lat ?? null, a.lng ?? null,
      a.radius_km ?? null, a.deadline_days ?? null, a.status ?? null, a.sort ?? null, limit, offset],
  );
  return r.rows;
}

// Hasil draw publik: pemenang dengan nama tersamar.
export async function getWinners(pool, giveawayId) {
  const g = (await pool.query('select id, status from giveaways where id = $1', [giveawayId])).rows[0];
  if (!g) return fail('not_found');
  if (g.status !== 'drawn') return ok({ drawn: false, winners: [] });
  const w = await pool.query(
    `select w.rank, t.ticket_number, u.username
       from winners w join tickets t on t.id = w.ticket_id join users u on u.id = w.user_id
      where w.giveaway_id = $1 order by w.rank`,
    [g.id],
  );
  return ok({ drawn: true, winners: w.rows.map((r) => ({ rank: r.rank, ticket_number: r.ticket_number, name: maskName(r.username) })) });
}

// Bahan verifikasi untuk aplikasi (publik; tanpa data pribadi). Daftar tiket baru dibuka setelah draw.
export async function getVerificationData(pool, giveawayId) {
  const g = (await pool.query('select id, winner_count, status, seed_hash from giveaways where id = $1', [giveawayId])).rows[0];
  if (!g) return fail('not_found');
  const last = (await pool.query('select max(block_index) as m from draw_chain where giveaway_id = $1', [g.id])).rows[0].m;
  const chain = (
    await pool.query(
      `select block_index, block_type, giveaway_id, draw_id, seed_hash, seed, winner_count, total_tickets,
              tickets_hash, winning_tickets, ts_ms, previous_hash, block_hash
         from draw_chain where block_index <= $1 order by block_index`,
      [last ?? 0],
    )
  ).rows;
  const first = (
    await pool.query('select floor(extract(epoch from min(created_at)) * 1000)::bigint as ms from tickets where giveaway_id = $1', [g.id])
  ).rows[0].ms;

  let tickets = null;
  if (g.status === 'drawn') {
    const t = await pool.query('select ticket_number, user_id from tickets where giveaway_id = $1 order by ticket_number', [g.id]);
    tickets = t.rows.map((r) => [r.ticket_number, ownerKey(r.user_id, g.id)]);
  }
  return ok({
    giveaway: { id: g.id, winner_count: g.winner_count, status: g.status, seed_hash: g.seed_hash },
    chain,
    first_ticket_ms: first,
    tickets,
  });
}
