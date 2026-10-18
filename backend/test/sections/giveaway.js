import { describe, expect, it } from 'vitest';
import { giveawayBody, login, mkGiveaway, register, sha, sqlstateOf } from '../helpers.js';

export function giveawaySections(ctx) {
  const { api, su, s } = ctx;
  const one = async (sql, params) => (await su.query(sql, params)).rows[0];
  const count = async (sql, params) => (await one(sql, params)).n;

  describe('3. Admin, giveaway, commit block', () => {
    it('non-admin membuat giveaway -> 403 forbidden', async () => {
      const r = await api.raw('post', '/admin/giveaways', { token: s.aliceTok, body: giveawayBody() });
      expect(r.status).toBe(403);
      expect(r.body).toEqual({ ok: false, error: 'forbidden' });
    });
    it('admin masuk', async () => {
      await register(api, 'admin01', 'admin@example.com', 'Adm1nPass!', 'Admin');
      await su.query("update users set role='admin' where username='admin01'");
      s.adm = (await login(api, 'admin01', 'Adm1nPass!')).token;
      expect(s.adm).toHaveLength(64);
    });
    it('admin membuat giveaway', async () => {
      const g1 = await mkGiveaway(api, s.adm, { title: 'Tech Prize', winners: 2, maxTickets: 3 });
      expect(g1.ok).toBe(true);
      expect(g1.created).toBe(true);
      s.gid1 = g1.giveaway_id;
    });
    it('seed rahasia tersimpan', async () => {
      const r = await one('select seed, length(seed)::int as n from giveaway_secrets where giveaway_id=$1', [s.gid1]);
      expect(r.n).toBe(64);
      s.seed1 = r.seed;
    });
    it('seed_hash di giveaway = SHA-256(seed)', async () => {
      expect((await one('select seed_hash from giveaways where id=$1', [s.gid1])).seed_hash).toBe(sha(s.seed1));
    });
    it('commit block terbentuk (seed belum dibuka)', async () => {
      const c = (await su.query('select block_type, seed_hash, seed, winner_count, block_index from draw_chain where giveaway_id=$1', [s.gid1])).rows;
      expect(c).toHaveLength(1);
      expect(c[0].block_type).toBe('commit');
      expect(c[0].seed).toBeNull();
      expect(c[0].seed_hash).toBe(sha(s.seed1));
      expect(c[0].winner_count).toBe(2);
    });
    it('block genesis memakai previous_hash nol', async () => {
      expect((await one('select previous_hash from draw_chain where block_index=1')).previous_hash).toBe('0'.repeat(64));
    });
    it('urutan waktu tidak valid ditolak', async () => {
      const bad = await mkGiveaway(api, s.adm, { title: 'X', start: 2 * 3_600_000, end: 3_600_000, draw: 3 * 3_600_000 });
      expect(bad.error).toBe('invalid_input');
    });
    it('winner_count 0 ditolak', async () => {
      expect((await mkGiveaway(api, s.adm, { winners: 0 })).error).toBe('invalid_input');
    });
    it('kategori tidak dikenal ditolak', async () => {
      expect((await mkGiveaway(api, s.adm, { category: 'senjata' })).error).toBe('invalid_input');
    });
    it('tanggal tidak valid ditolak (ditangkap database, tanpa 500)', async () => {
      const r = await api.raw('post', '/admin/giveaways', { token: s.adm, body: { ...giveawayBody(), start_at: "bukan tanggal" } });
      expect(r.status).toBe(200);
      expect(r.body.error).toBe('invalid_input');
    });
    it('waktu tanpa zona (Z/offset) ditolak', async () => {
      const r = await api.post('/admin/giveaways', { token: s.adm, body: { ...giveawayBody(), start_at: '2030-01-01T10:00:00' } });
      expect([r.error, r.field]).toEqual(['invalid_input', 'start_at']);
    });
    it('giveaway gagal tidak meninggalkan seed/block yatim', async () => {
      expect(await count('select count(*)::int n from giveaway_secrets')).toBe(1);
      expect(await count('select count(*)::int n from draw_chain')).toBe(1);
      expect(await count('select count(*)::int n from giveaways')).toBe(1);
    });
    it('ubah judul diizinkan', async () => {
      const r = await api.post('/admin/giveaways', { token: s.adm, body: { id: s.gid1, title: 'Tech Prize v2' } });
      expect(r.ok).toBe(true);
      expect(r.created).toBe(false);
    });
    it('seed tidak berubah saat giveaway diubah', async () => {
      expect((await one('select seed from giveaway_secrets where giveaway_id=$1', [s.gid1])).seed).toBe(s.seed1);
    });
    it('jumlah block tidak bertambah saat diubah', async () => {
      expect(await count('select count(*)::int n from draw_chain where giveaway_id=$1', [s.gid1])).toBe(1);
    });
    it('winner_count terkunci setelah giveaway mulai', async () => {
      const r = await api.post('/admin/giveaways', { token: s.adm, body: { id: s.gid1, winner_count: 5 } });
      expect(r.error).toBe('winner_count_locked');
    });
    it('start_at terkunci setelah giveaway mulai', async () => {
      const r = await api.post('/admin/giveaways', { token: s.adm, body: { id: s.gid1, start_at: new Date(Date.now() - 1000).toISOString() } });
      expect(r.error).toBe('start_at_locked');
    });
    it('ubah giveaway yang tidak ada -> not_found', async () => {
      const r = await api.post('/admin/giveaways', { token: s.adm, body: { id: '00000000-0000-4000-8000-000000000000', title: 'x' } });
      expect(r.error).toBe('not_found');
    });
    it('block draw_chain tidak bisa diubah (UPDATE)', async () => {
      expect(await sqlstateOf(() => su.query('update draw_chain set ts_ms = 1'))).toBe('42501');
    });
    it('block draw_chain tidak bisa dihapus (DELETE)', async () => {
      expect(await sqlstateOf(() => su.query('delete from draw_chain'))).toBe('42501');
    });
    it('draw_chain tidak bisa di-TRUNCATE', async () => {
      expect(await sqlstateOf(() => su.query('truncate draw_chain'))).toBe('42501');
    });
  });
}
