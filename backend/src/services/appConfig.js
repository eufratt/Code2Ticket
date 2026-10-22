import { cpLen, ok } from '../lib/util.js';

const EMAIL_RE = /^[^\s@\x00-\x1f\x7f]+@[^\s@\x00-\x1f\x7f]+\.[^\s@\x00-\x1f\x7f]+$/;
const CONTROL_RE = /[\x00-\x1f\x7f]/;

// Nilai tidak valid dianggap kosong (null), bukan dipotong.
export const cleanEmail = (v) => {
  const s = String(v ?? '').trim();
  return s.length > 0 && s.length <= 254 && EMAIL_RE.test(s) ? s : null;
};
export const cleanNote = (v) => {
  const s = String(v ?? '').trim();
  return s.length > 0 && cpLen(s) <= 300 && !CONTROL_RE.test(s) ? s : null;
};

// Publik, baca-saja. Hanya dua kunci ini yang pernah dibaca dari app_config (kunci lain, mis. demo_draw_enabled, tidak bocor).
export async function getOrganizerContact(pool) {
  const { rows } = await pool.query("select key, value from app_config where key in ('organizer_contact_email', 'organizer_contact_note')");
  const v = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  return ok({ email: cleanEmail(v.organizer_contact_email), note: cleanNote(v.organizer_contact_note) });
}
