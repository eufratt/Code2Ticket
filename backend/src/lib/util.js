import crypto from 'node:crypto';

export const sha256Hex = (s) => crypto.createHash('sha256').update(s, 'utf8').digest('hex');
export const timingSafeEqualStr = (a, b) =>
  crypto.timingSafeEqual(crypto.createHash('sha256').update(String(a)).digest(), crypto.createHash('sha256').update(String(b)).digest());
export const randomHex = (bytes) => crypto.randomBytes(bytes).toString('hex');

// Setara trim() Postgres: hanya spasi. char_length() menghitung code point, bukan UTF-16.
export const pgTrim = (s) => String(s ?? '').replace(/^ +| +$/g, '');
export const cpLen = (s) => [...s].length;

export const TOKEN_RE = /^[0-9a-f]{64}$/;

export const ok = (extra = {}) => ({ ok: true, ...extra });
export const fail = (error, extra = {}) => ({ ok: false, error, ...extra });
export const invalid = (field) => fail('invalid_input', field ? { field } : {});

export class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}
export const invalidSession = () => new HttpError(401, 'invalid_session');
export const forbidden = () => new HttpError(403, 'forbidden');

// Hasil zod -> {ok:false,error:'invalid_input',field} untuk field pertama yang salah.
export function parseInput(schema, data) {
  const r = schema.safeParse(data ?? {});
  if (r.success) return { data: r.data };
  const p = r.error.issues[0]?.path?.[0];
  return { error: invalid(typeof p === 'string' ? p : undefined) };
}
