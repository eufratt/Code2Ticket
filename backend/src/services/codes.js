import crypto from 'node:crypto';
import { z } from 'zod';
import { withTx } from '../db.js';
import { fail, invalid, ok } from '../lib/util.js';

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 32 karakter, tanpa I/O/0/1

// 256 habis dibagi 32, jadi tiap byte % 32 seragam (tanpa modulo bias).
export function randomCode() {
  const b = crypto.randomBytes(12);
  let out = '';
  for (let i = 0; i < 12; i++) {
    out += ALPHABET[b[i] % 32];
    if (i === 3 || i === 7) out += '-';
  }
  return out;
}

const countSchema = z.int().min(1).max(1000);
const geoSchema = z.object({
  geo_lat: z.number().min(-90).max(90).nullish(),
  geo_lng: z.number().min(-180).max(180).nullish(),
  geo_radius_km: z.number().positive().max(99999).nullish(),
});

export async function generateCodes(pool, giveawayId, body) {
  const count = countSchema.safeParse(body?.count);
  if (!count.success) return invalid('count');
  const geo = geoSchema.safeParse(body ?? {});
  if (!geo.success) return invalid('geo');
  const { geo_lat: lat = null, geo_lng: lng = null, geo_radius_km: rad = null } = geo.data;
  if ((lat === null) !== (lng === null) || (lat === null) !== (rad === null)) return invalid('geo');

  const g = (await pool.query('select id, status from giveaways where id = $1', [giveawayId])).rows[0];
  if (!g) return fail('not_found');
  if (g.status === 'drawn') return fail('giveaway_drawn');

  const n = count.data;
  const codes = await withTx(pool, async (c) => {
    const out = [];
    const maxAttempts = n * 20;
    let tried = 0;
    while (out.length < n && tried < maxAttempts) {
      const need = Math.min(n - out.length, maxAttempts - tried);
      tried += need;
      const batch = [...new Set(Array.from({ length: need }, randomCode))];
      const r = await c.query(
        `insert into codes(giveaway_id, code, geo_lat, geo_lng, geo_radius_km)
         select $1, x, $3::float8, $4::float8, $5::numeric from unnest($2::text[]) as x
         on conflict (code) do nothing returning code`,
        [g.id, batch, lat, lng, rad],
      );
      out.push(...r.rows.map((x) => x.code));
    }
    return out;
  });
  return ok({ codes });
}

export async function listCodes(pool, giveawayId) {
  const r = await pool.query(
    'select code, is_used, used_at, geo_radius_km from codes where giveaway_id = $1 order by created_at, code',
    [giveawayId],
  );
  return r.rows;
}
