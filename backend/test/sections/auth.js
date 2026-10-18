import crypto from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { clientHash, login, register, sha } from '../helpers.js';

export function authSections(ctx) {
  const { api, su, s } = ctx;
  const one = async (sql, params) => (await su.query(sql, params)).rows[0];

  describe('1. Register dan salt', () => {
    it('register berhasil', async () => {
      const r = await register(api, 'alice', 'alice@example.com', 'Passw0rd!1', 'Alice A');
      expect(r.ok).toBe(true);
      expect(r.user_id).toMatch(/^[0-9a-f-]{36}$/);
    });
    it('username duplikat (beda huruf besar) ditolak', async () => {
      expect((await register(api, 'ALICE', 'x@example.com', 'Passw0rd!1')).error).toBe('username_taken');
    });
    it('email duplikat ditolak', async () => {
      expect((await register(api, 'alice2', 'ALICE@example.com', 'Passw0rd!1')).error).toBe('email_taken');
    });
    it('username pendek ditolak', async () => {
      expect((await register(api, 'abc', 'b@example.com', 'Passw0rd!1')).field).toBe('username');
    });
    it('email tidak valid ditolak', async () => {
      expect((await register(api, 'bobby', 'bukan-email', 'Passw0rd!1')).field).toBe('email');
    });
    it('hash non-hex ditolak (password plaintext tidak diterima)', async () => {
      const bad = await api.post('/auth/register', {
        body: { username: 'carol1', email: 'c@example.com', full_name: 'Carol', salt: crypto.randomBytes(16).toString('hex'), password_hash: 'plaintext-password' },
      });
      expect(bad.field).toBe('password_hash');
    });
    it('body kosong/bukan objek -> invalid_input, bukan 500', async () => {
      const r = await api.raw('post', '/auth/register', { body: {} });
      expect(r.status).toBe(200);
      expect(r.body.error).toBe('invalid_input');
    });
    it('password disimpan sebagai bcrypt', async () => {
      expect((await one("select password_hash from users where username='alice'")).password_hash.startsWith('$2')).toBe(true);
    });
    it('hash klien tidak tersimpan apa adanya', async () => {
      const u = await one("select password_hash, salt from users where username='alice'");
      expect(u.password_hash).not.toBe(clientHash('Passw0rd!1', u.salt));
    });
    it('salt sama untuk username dan email', async () => {
      const s1 = (await api.post('/auth/salt', { body: { identifier: 'alice' } })).salt;
      const s2 = (await api.post('/auth/salt', { body: { identifier: 'ALICE@example.com' } })).salt;
      expect(s1).toBe(s2);
      expect(s1).toHaveLength(32);
      s.realSalt = s1;
    });
    it('salt palsu konsisten dan berformat sama', async () => {
      const f1 = (await api.post('/auth/salt', { body: { identifier: 'tidak_ada' } })).salt;
      const f2 = (await api.post('/auth/salt', { body: { identifier: 'tidak_ada' } })).salt;
      expect(f1).toBe(f2);
      expect(f1).toHaveLength(32);
      expect(f1).not.toBe(s.realSalt);
    });
  });

  describe('2. Login, kunci akun, session', () => {
    it('password salah -> invalid_credentials, sisa 4', async () => {
      const r = await login(api, 'alice', 'salah');
      expect(r.error).toBe('invalid_credentials');
      expect(r.attempts_left).toBe(4);
    });
    it('email dan username berbagi hitungan gagal', async () => {
      expect((await login(api, 'alice@example.com', 'salah')).attempts_left).toBe(3);
    });
    it('percobaan ke-4 masih invalid_credentials', async () => {
      await login(api, 'alice', 'salah');
      expect((await login(api, 'alice', 'salah')).attempts_left).toBe(1);
    });
    it('percobaan ke-5 -> locked 15 menit', async () => {
      const r = await login(api, 'alice', 'salah');
      expect(r.error).toBe('locked');
      expect(r.retry_after_seconds).toBe(900);
    });
    it('password benar saat terkunci tetap ditolak', async () => {
      expect((await login(api, 'alice', 'Passw0rd!1')).error).toBe('locked');
    });
    it('login berhasil setelah kunci kedaluwarsa', async () => {
      await su.query("update login_attempts set locked_until = now() - interval '1 second'");
      const r = await login(api, 'alice', 'Passw0rd!1');
      expect(r.ok).toBe(true);
      expect(r.token).toHaveLength(64);
      s.aliceTok = r.token;
      s.aliceLogin = r;
    });
    it('data user dikembalikan tanpa hash/salt', () => {
      expect(s.aliceLogin.user).not.toHaveProperty('password_hash');
      expect(s.aliceLogin.user).not.toHaveProperty('salt');
    });
    it('login tidak ada akun -> pesan sama', async () => {
      expect((await login(api, 'hantu', 'x')).error).toBe('invalid_credentials');
    });
    it('akun tidak ada ikut terkunci setelah 5 gagal (tidak membedakan)', async () => {
      let r;
      for (let i = 0; i < 5; i++) r = await login(api, 'hantu', 'x');
      expect(r.error).toBe('locked');
    });
    it('token tidak disimpan plaintext', async () => {
      expect((await one('select count(*)::int n from sessions where token_hash = $1', [s.aliceTok])).n).toBe(0);
    });
    it('token disimpan sebagai SHA-256', async () => {
      expect((await one('select count(*)::int n from sessions where token_hash = $1', [sha(s.aliceTok)])).n).toBe(1);
    });
    it('sesi berlaku 7 hari', async () => {
      const r = await one("select expires_at - now() > interval '6 days 23 hours' and expires_at - now() <= interval '7 days' as okk from sessions where token_hash = $1", [sha(s.aliceTok)]);
      expect(r.okk).toBe(true);
    });
    it('GET /auth/me (validate_session) ok', async () => {
      const r = await api.get('/auth/me', { token: s.aliceTok });
      expect(r.ok).toBe(true);
      expect(r.user.username).toBe('alice');
    });
    it('GET /auth/me token palsu -> 401 invalid_session', async () => {
      const r = await api.raw('get', '/auth/me', { token: '0'.repeat(64) });
      expect(r.status).toBe(401);
      expect(r.body).toEqual({ ok: false, error: 'invalid_session' });
    });
    it('endpoint bertoken tanpa header Authorization -> 401', async () => {
      const r = await api.raw('get', '/tickets');
      expect(r.status).toBe(401);
      expect(r.body.error).toBe('invalid_session');
    });
    it('endpoint bertoken dengan token palsu -> 401 invalid_session', async () => {
      const r = await api.raw('get', '/tickets', { token: '0'.repeat(64) });
      expect(r.status).toBe(401);
      expect(r.body.error).toBe('invalid_session');
    });
    it('token format salah -> 401', async () => {
      expect((await api.raw('get', '/tickets', { token: 'abc' })).status).toBe(401);
    });
    it('session kedaluwarsa ditolak', async () => {
      await su.query("update sessions set expires_at = now() - interval '1 second' where token_hash = $1", [sha(s.aliceTok)]);
      expect((await api.raw('get', '/auth/me', { token: s.aliceTok })).status).toBe(401);
    });
    it('session tidak valid setelah logout', async () => {
      const tok = (await login(api, 'alice', 'Passw0rd!1')).token;
      expect((await api.post('/auth/logout', { token: tok })).ok).toBe(true);
      expect((await api.raw('get', '/auth/me', { token: tok })).status).toBe(401);
      s.aliceTok = (await login(api, 'alice', 'Passw0rd!1')).token;
    });
    it('logout dengan token palsu/tanpa token tetap ok (seperti rpc_logout)', async () => {
      expect((await api.post('/auth/logout', { token: 'bukan-token' })).ok).toBe(true);
      expect((await api.post('/auth/logout', {})).ok).toBe(true);
    });
    it('last_seen_at diperbarui paling cepat tiap 1 menit', async () => {
      const row = await one('select last_seen_at from sessions where token_hash = $1', [sha(s.aliceTok)]);
      await api.get('/auth/me', { token: s.aliceTok });
      const row2 = await one('select last_seen_at from sessions where token_hash = $1', [sha(s.aliceTok)]);
      expect(row.last_seen_at === null ? row2.last_seen_at !== null : row2.last_seen_at.getTime() === row.last_seen_at.getTime()).toBe(true);
    });
  });
}
