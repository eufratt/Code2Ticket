import { z } from 'zod';
import { withTx } from '../db.js';
import { appendBlock } from '../lib/chain.js';
import { cpLen, fail, invalid, ok, parseInput, randomHex, sha256Hex } from '../lib/util.js';

const CATEGORIES = ['tech', 'gaming', 'travel', 'fashion', 'food', 'lifestyle', 'other'];

// Kesalahan nilai dari database yang dipetakan ke invalid_input (sama seperti blok exception SQL lama):
// check_violation, not_null_violation, invalid_text_representation, datetime_field_overflow,
// invalid_datetime_format, numeric_value_out_of_range.
const INPUT_ERROR_CODES = new Set(['23514', '23502', '22P02', '22008', '22007', '22003']);

// Nilai hadiah: rupiah bulat positif (mata uang dasar), batas atas sama dengan CHECK di 08_prize_value_idr.sql.
export const MAX_PRIZE_IDR = 100_000_000_000;
const prizeIdr = z.number().int().min(1).max(MAX_PRIZE_IDR);
// Cara mendapatkan kode: wajib untuk giveaway baru, 10..2000 karakter setelah trim.
const howTo = z.string().transform((s) => s.trim()).refine((s) => cpLen(s) >= 10 && cpLen(s) <= 2000);
// Tautan penyelenggara: hanya https absolut, maks. 500, tanpa kredensial/spasi/karakter kontrol, host domain valid.
const HOST_RE = /^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$/i;
export function isHttpsUrl(s) {
  if (s.length > 500 || /[\s\x00-\x1f\x7f]/.test(s) || !/^https:\/\//i.test(s)) return false;
  try {
    const u = new URL(s);
    return u.protocol === 'https:' && !u.username && !u.password && HOST_RE.test(u.hostname);
  } catch {
    return false;
  }
}
// '' / null = tidak ada (di ubah: mengosongkan). Nilai lain di-trim lalu harus lolos isHttpsUrl.
const orgUrl = z.union([z.literal(''), z.null(), z.string().transform((s) => s.trim()).refine(isHttpsUrl)]);
const numLike = z.union([z.number().finite(), z.string().regex(/^-?\d+(\.\d+)?$/)]);
// Waktu wajib menyertakan zona (Z atau +hh[:mm]) supaya tidak bergantung pada zona sesi database.
const ts = z.string().max(64).regex(/(Z|[+-]\d{2}(:?\d{2})?)$/i);

const fields = {
  title: z.string().refine((s) => cpLen(s) >= 1 && cpLen(s) <= 120),
  description: z.string().max(5000),
  organizer: z.string().max(200),
  category: z.enum(CATEGORIES),
  prize_name: z.string().min(1).max(200),
  prize_value_idr: prizeIdr,
  latitude: z.number().min(-90).max(90).nullable(),
  longitude: z.number().min(-180).max(180).nullable(),
  address: z.string().max(500).nullable(),
  radius_km: numLike.nullable(),
  start_at: ts,
  end_at: ts,
  draw_at: ts,
  winner_count: z.number().int().min(1).max(100),
  max_tickets_per_user: z.number().int().min(1),
  how_to_participate: howTo,
  organizer_url: orgUrl,
  redeem_geo_restricted: z.boolean(),
};
const idField = z.union([z.uuid(), z.literal(''), z.null()]).optional();

const createSchema = z.object({
  id: idField,
  title: fields.title, description: fields.description.nullish(), organizer: fields.organizer.nullish(),
  category: fields.category, prize_name: fields.prize_name, prize_value_idr: fields.prize_value_idr,
  latitude: fields.latitude.optional(), longitude: fields.longitude.optional(), address: fields.address.optional(),
  radius_km: fields.radius_km.optional(), start_at: fields.start_at, end_at: fields.end_at, draw_at: fields.draw_at,
  winner_count: fields.winner_count, max_tickets_per_user: fields.max_tickets_per_user.nullish(),
  how_to_participate: fields.how_to_participate, organizer_url: fields.organizer_url.optional(),
  redeem_geo_restricted: fields.redeem_geo_restricted.nullish(),
});

// Ubah: semua field opsional; null/absen = pertahankan (coalesce), kecuali lokasi/alamat/radius
// yang boleh dikosongkan secara eksplisit.
const updateSchema = z.object({
  id: z.uuid(),
  title: fields.title.nullish(), description: fields.description.nullish(), organizer: fields.organizer.nullish(),
  category: fields.category.nullish(), prize_name: fields.prize_name.nullish(), prize_value_idr: fields.prize_value_idr.nullish(),
  latitude: fields.latitude.optional(), longitude: fields.longitude.optional(), address: fields.address.optional(),
  radius_km: fields.radius_km.optional(), start_at: ts.nullish(), end_at: ts.nullish(), draw_at: ts.nullish(),
  winner_count: fields.winner_count.nullish(), max_tickets_per_user: fields.max_tickets_per_user.nullish(),
  how_to_participate: fields.how_to_participate.nullish(), organizer_url: fields.organizer_url.optional(),
  redeem_geo_restricted: fields.redeem_geo_restricted.nullish(),
});

// Batas lokasi tukar kode memakai lokasi giveaway: wajib lintang, bujur, dan radius > 0.
const geoComplete = (lat, lng, rad) => lat != null && lng != null && rad != null && Number(rad) > 0;

export async function upsertGiveaway(pool, admin, body) {
  const b = body ?? {};
  const creating = b.id == null || b.id === '';
  const p = parseInput(creating ? createSchema : updateSchema, b);
  if (p.error) return p.error;
  try {
    return await withTx(pool, (c) => (creating ? createGiveaway(c, admin, p.data) : updateGiveaway(c, p.data, b)));
  } catch (e) {
    if (INPUT_ERROR_CODES.has(e.code)) return fail('invalid_input');
    throw e;
  }
}

// Seed dibuat sekali di sini; hash-nya langsung di-commit ke hash-chain (dalam transaksi yang sama,
// jadi giveaway yang gagal tidak meninggalkan seed/block yatim).
async function createGiveaway(c, admin, d) {
  const restricted = d.redeem_geo_restricted ?? false;
  if (restricted && !geoComplete(d.latitude, d.longitude, d.radius_km)) return invalid('redeem_geo_restricted');
  const seed = randomHex(32);
  const seedHash = sha256Hex(seed);
  const g = await c.query(
    `insert into giveaways(title, description, organizer, category, prize_name, prize_value_idr,
        latitude, longitude, address, radius_km, start_at, end_at, draw_at, winner_count,
        max_tickets_per_user, seed_hash, status, created_by, how_to_participate, organizer_url, redeem_geo_restricted)
     values ($1, coalesce($2::text, ''), coalesce($3::text, ''), $4, $5, $6::numeric,
        $7::float8, $8::float8, $9::text, $10::numeric, $11::timestamptz, $12::timestamptz, $13::timestamptz, $14::int,
        coalesce($15::int, 10), $16,
        case when now() < $11::timestamptz then 'upcoming' when now() < $12::timestamptz then 'active' else 'waiting_draw' end,
        $17, $18::text, $19::text, $20::boolean)
     returning id`,
    [d.title, d.description ?? null, d.organizer ?? null, d.category, d.prize_name, d.prize_value_idr,
      d.latitude ?? null, d.longitude ?? null, d.address ?? null, d.radius_km ?? null, d.start_at, d.end_at, d.draw_at,
      d.winner_count, d.max_tickets_per_user ?? null, seedHash, admin.id, d.how_to_participate, d.organizer_url || null, restricted],
  );
  const id = g.rows[0].id;
  await c.query('insert into giveaway_secrets(giveaway_id, seed) values ($1, $2)', [id, seed]);
  await appendBlock(c, { block_type: 'commit', giveaway_id: id, seed_hash: seedHash, winner_count: d.winner_count });
  return ok({ giveaway_id: id, created: true });
}

// Seed tidak pernah dibuat ulang saat mengubah.
async function updateGiveaway(c, d, raw) {
  const has = (k) => Object.hasOwn(raw, k);
  const g = (
    await c.query(
      `select id, status, winner_count, now() >= start_at as started,
              ticket_counter, redeem_geo_restricted, latitude, longitude, radius_km,
              ($2::timestamptz is distinct from start_at) as start_changed
         from giveaways where id = $1 for update`,
      [d.id, has('start_at') ? (d.start_at ?? null) : null],
    )
  ).rows[0];
  if (!g) return fail('not_found');
  if (g.status === 'drawn') return fail('giveaway_drawn');
  if (g.started) {
    if (has('winner_count') && (d.winner_count ?? null) !== g.winner_count) return fail('winner_count_locked');
    if (has('start_at') && g.start_changed) return fail('start_at_locked');
  }
  const restricted = d.redeem_geo_restricted ?? g.redeem_geo_restricted;
  const lat = has('latitude') ? d.latitude : g.latitude;
  const lng = has('longitude') ? d.longitude : g.longitude;
  const rad = has('radius_km') ? d.radius_km : g.radius_km;
  if (restricted && !geoComplete(lat, lng, rad)) return invalid('redeem_geo_restricted');
  // Setelah ada tiket terbit, aturan lokasi tidak boleh berubah (peserta awal dan akhir harus diperlakukan sama).
  const geoChanged = restricted !== g.redeem_geo_restricted
    || (g.redeem_geo_restricted && (lat !== g.latitude || lng !== g.longitude || Number(rad) !== Number(g.radius_km)));
  if (g.ticket_counter > 0 && geoChanged) return fail('redeem_geo_locked');
  await c.query(
    `update giveaways set
        title = coalesce($2::text, title), description = coalesce($3::text, description),
        organizer = coalesce($4::text, organizer), category = coalesce($5::text, category),
        prize_name = coalesce($6::text, prize_name), prize_value_idr = coalesce($7::numeric, prize_value_idr),
        latitude  = case when $8::boolean  then $9::float8  else latitude  end,
        longitude = case when $10::boolean then $11::float8 else longitude end,
        address   = case when $12::boolean then $13::text   else address   end,
        radius_km = case when $14::boolean then $15::numeric else radius_km end,
        start_at = coalesce($16::timestamptz, start_at), end_at = coalesce($17::timestamptz, end_at),
        draw_at = coalesce($18::timestamptz, draw_at),
        winner_count = coalesce($19::int, winner_count),
        max_tickets_per_user = coalesce($20::int, max_tickets_per_user),
        how_to_participate = coalesce($21::text, how_to_participate),
        organizer_url = case when $22::boolean then $23::text else organizer_url end,
        redeem_geo_restricted = coalesce($24::boolean, redeem_geo_restricted),
        status = case when now() < coalesce($16::timestamptz, start_at) then 'upcoming'
                      when now() < coalesce($17::timestamptz, end_at) then 'active' else 'waiting_draw' end
      where id = $1`,
    [d.id, d.title ?? null, d.description ?? null, d.organizer ?? null, d.category ?? null, d.prize_name ?? null,
      d.prize_value_idr ?? null, has('latitude'), d.latitude ?? null, has('longitude'), d.longitude ?? null,
      has('address'), d.address ?? null, has('radius_km'), d.radius_km ?? null, d.start_at ?? null, d.end_at ?? null,
      d.draw_at ?? null, d.winner_count ?? null, d.max_tickets_per_user ?? null, d.how_to_participate ?? null,
      has('organizer_url'), d.organizer_url || null, d.redeem_geo_restricted ?? null],
  );
  return ok({ giveaway_id: g.id, created: false });
}
