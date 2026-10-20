import { withTx } from '../db.js';
import { fail, invalid, ok } from '../lib/util.js';
import { userJson } from './users.js';

export const MAX_PHOTO_BYTES = 150 * 1024;
const EOI = Buffer.from([0xff, 0xd9]);

// JPEG sungguhan: penanda awal FF D8 FF dan penanda akhir FF D9 (isi mentah dari klien tidak dipercaya).
export function isJpeg(b) {
  return Buffer.isBuffer(b) && b.length > 4 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff && b.lastIndexOf(EOI) > 2;
}

// Membuang semua segmen APP1 (EXIF/GPS dan XMP) dari JPEG; segmen lain dan data gambar tidak diubah, jadi hasilnya tetap
// JPEG valid. Berjalan sampai SOS (awal data gambar); struktur yang tidak bisa dibaca -> null (ditolak, tidak dipercaya).
export function stripJpegMetadata(b) {
  const out = [b.subarray(0, 2)];
  let i = 2;
  while (i + 4 <= b.length) {
    if (b[i] !== 0xff) return null;
    const marker = b[i + 1];
    if (marker === 0xff) { i += 1; continue; } // byte pengisi
    if (marker === 0xd9 || (marker >= 0xd0 && marker <= 0xd8) || marker === 0x01) return null; // tanpa data gambar / tak lazim sebelum SOS
    const end = i + 2 + b.readUInt16BE(i + 2);
    if (end > b.length || end < i + 4) return null;
    if (marker === 0xda) {
      out.push(b.subarray(i)); // SOS + data entropi + EOI apa adanya
      return Buffer.concat(out);
    }
    if (marker !== 0xe1) out.push(b.subarray(i, end));
    i = end;
  }
  return null;
}

// Menyimpan foto sebagai biner di database; users.photo_url menunjuk ke GET /users/:id/photo dengan
// parameter versi (?v=) supaya klien memuat ulang gambar saat foto berganti.
export async function savePhoto(pool, user, body, contentType) {
  if (contentType !== 'image/jpeg') return invalid('content_type');
  if (!Buffer.isBuffer(body) || body.length === 0) return invalid('photo');
  if (body.length > MAX_PHOTO_BYTES) return fail('payload_too_large');
  if (!isJpeg(body)) return invalid('photo');
  // Lokasi/metadata di EXIF tidak boleh tersimpan atau terunduh publik, apa pun yang dikirim klien.
  const clean = stripJpegMetadata(body);
  if (!clean) return invalid('photo');
  return withTx(pool, async (c) => {
    const r = await c.query(
      `insert into user_photos(user_id, content_type, bytes, updated_at) values ($1, 'image/jpeg', $2, now())
       on conflict (user_id) do update set content_type = excluded.content_type, bytes = excluded.bytes, updated_at = excluded.updated_at
       returning floor(extract(epoch from updated_at) * 1000)::bigint as v`,
      [user.id, clean],
    );
    const u = (
      await c.query('update users set photo_url = $2 where id = $1 returning *', [user.id, `/users/${user.id}/photo?v=${r.rows[0].v}`])
    ).rows[0];
    return ok({ user: await userJson(c, u) });
  });
}

export async function getPhoto(pool, userId) {
  const r = await pool.query(
    'select content_type, bytes, floor(extract(epoch from updated_at) * 1000)::bigint as v from user_photos where user_id = $1',
    [userId],
  );
  return r.rows[0] ?? null;
}
