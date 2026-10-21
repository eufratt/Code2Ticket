import { describe, expect, it } from 'vitest';
import { genCodes, HOUR, login, mkGiveaway, redeem, register, sha } from '../helpers.js';

export function redeemSections(ctx) {
  const { api, su, s } = ctx;
  const one = async (sql, params) => (await su.query(sql, params)).rows[0];

  describe('4. Kode dan input kode', () => {
    it('40 kode unik dengan format XXXX-XXXX-XXXX', async () => {
      s.codes = await genCodes(api, s.adm, s.gid1, 40);
      expect(new Set(s.codes).size).toBe(40);
      expect(s.codes.every((c) => /^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/.test(c))).toBe(true);
    });
    it('generate kode oleh non-admin ditolak (403)', async () => {
      const r = await api.raw('post', `/admin/giveaways/${s.gid1}/codes`, { token: s.aliceTok, body: { count: 1 } });
      expect(r.status).toBe(403);
    });
    it('generate 0 kode ditolak', async () => {
      expect((await api.post(`/admin/giveaways/${s.gid1}/codes`, { token: s.adm, body: { count: 0 } })).error).toBe('invalid_input');
    });
    it('generate 1001 kode / geo tidak lengkap ditolak', async () => {
      expect((await api.post(`/admin/giveaways/${s.gid1}/codes`, { token: s.adm, body: { count: 1001 } })).error).toBe('invalid_input');
      const r = await api.post(`/admin/giveaways/${s.gid1}/codes`, { token: s.adm, body: { count: 1, geo_lat: 1 } });
      expect(r.field).toBe('geo');
    });
    it('daftar kode (admin)', async () => {
      const l = await api.get(`/admin/giveaways/${s.gid1}/codes`, { token: s.adm });
      expect(l).toHaveLength(40);
      expect(l[0]).toEqual({ code: expect.any(String), is_used: false, used_at: null, geo_radius_km: null });
    });

    it('format salah -> invalid_format', async () => {
      expect((await redeem(api, s.aliceTok, 'ABC')).error).toBe('invalid_format');
    });
    it('kode tidak ada -> code_not_found', async () => {
      expect((await redeem(api, s.aliceTok, 'AAAA-BBBB-CCCC')).error).toBe('code_not_found');
    });
    it('kode huruf kecil tanpa strip diterima, tiket #1', async () => {
      const r = await redeem(api, s.aliceTok, s.codes[0].toLowerCase().replace(/-/g, ' '));
      expect(r.ok).toBe(true);
      expect(r.ticket.ticket_number).toBe(1);
      expect(r.ticket.result).toBe('eligible');
    });
    it('kode dipakai ulang -> code_used', async () => {
      expect((await redeem(api, s.aliceTok, s.codes[0])).error).toBe('code_used');
    });
    it('tiket berurutan #2', async () => {
      expect((await redeem(api, s.aliceTok, s.codes[1])).ticket.ticket_number).toBe(2);
    });
    it('tiket berurutan #3', async () => {
      expect((await redeem(api, s.aliceTok, s.codes[2])).ticket.ticket_number).toBe(3);
    });
    it('batas 3 tiket per user -> ticket_limit', async () => {
      expect((await redeem(api, s.aliceTok, s.codes[3])).error).toBe('ticket_limit');
    });
    it('kode yang ditolak karena batas tetap belum terpakai', async () => {
      expect((await one('select is_used from codes where code=$1', [s.codes[3]])).is_used).toBe(false);
    });
    it('GET /tickets: 3 tiket, eligible, kode disamarkan', async () => {
      const mine = await api.get('/tickets', { token: s.aliceTok });
      expect(mine).toHaveLength(3);
      expect(mine.every((t) => t.result === 'eligible')).toBe(true);
      expect(mine[0].code_masked.startsWith('****-****-')).toBe(true);
    });
    it('notifikasi tiket dibuat', async () => {
      const n = await api.get('/notifications', { token: s.aliceTok });
      expect(n).toHaveLength(3);
      expect(n[0].type).toBe('ticket_created');
      expect(n[0].body).toMatch(/^Tiket #00000[1-3] untuk Tech Prize v2\.$/);
    });
    it('badge first_ticket', async () => {
      expect((await api.get('/auth/me', { token: s.aliceTok })).user.badges).toContain('first_ticket');
    });
    it('badge early_bird hanya 24 jam pertama (giveaway mulai 1 jam lalu)', async () => {
      expect((await api.get('/auth/me', { token: s.aliceTok })).user.badges).toContain('early_bird');
    });
    it('tanpa session -> 401', async () => {
      expect((await api.raw('post', '/codes/redeem', { body: { code: s.codes[5] } })).status).toBe(401);
    });
    it('kode bukan string -> invalid_format (tercatat sebagai kegagalan), bukan 500', async () => {
      await register(api, 'weirdo1', 'weirdo@example.com', 'Passw0rd!1', 'W');
      const tok = (await login(api, 'weirdo1', 'Passw0rd!1')).token;
      const r = await api.raw('post', '/codes/redeem', { token: tok, body: { code: 12345 } });
      expect(r.status).toBe(200);
      expect(r.body.error).toBe('invalid_format');
    });

    it('pembatasan: kegagalan ke-6 dalam 10 menit -> rate_limited (walau kode benar)', async () => {
      await register(api, 'bobby', 'bobby@example.com', 'Passw0rd!1', 'Bobby');
      s.bobTok = (await login(api, 'bobby', 'Passw0rd!1')).token;
      for (let i = 0; i < 5; i++) await redeem(api, s.bobTok, `ZZZZ-ZZZZ-ZZZ${i}`);
      const r = await redeem(api, s.bobTok, s.codes[10]);
      expect(r.error).toBe('rate_limited');
      expect(r.retry_after_seconds).toBeGreaterThan(0);
    });
    it('rate limit lepas setelah 10 menit', async () => {
      await su.query("update code_attempts set attempted_at = now() - interval '11 minutes'");
      expect((await redeem(api, s.bobTok, s.codes[10])).ok).toBe(true);
    });

    it('kode geo tanpa lokasi -> location_required', async () => {
      s.g2 = await mkGiveaway(api, s.adm, { title: 'Geo Prize', winners: 1, category: 'travel', lat: -6.2, lng: 106.8 });
      s.gcodes = await genCodes(api, s.adm, s.g2.giveaway_id, 3, [-6.2, 106.8, 5]);
      expect((await redeem(api, s.bobTok, s.gcodes[0])).error).toBe('location_required');
    });
    it('kode geo di luar radius -> out_of_area', async () => {
      expect((await redeem(api, s.bobTok, s.gcodes[0], -6.9175, 107.6191)).error).toBe('out_of_area'); // Bandung
    });
    it('kode geo di dalam radius diterima', async () => {
      expect((await redeem(api, s.bobTok, s.gcodes[0], -6.205, 106.82)).ok).toBe(true);
    });
    it('jarak haversine JS = SQL lama (2-3 km)', async () => {
      const { distanceKm } = await import('../../src/lib/geo.js');
      const d = distanceKm(-6.2, 106.8, -6.205, 106.82);
      expect(d).toBeGreaterThan(2.0);
      expect(d).toBeLessThan(3.0);
      const sql = await one(
        `select 2 * 6371.0 * asin(sqrt(least(1.0, power(sin(radians($3::float8 - $1::float8) / 2), 2)
           + cos(radians($1::float8)) * cos(radians($3::float8)) * power(sin(radians($4::float8 - $2::float8) / 2), 2)))) as d`,
        [-6.2, 106.8, -6.205, 106.82],
      );
      expect(Math.abs(sql.d - d)).toBeLessThan(1e-9);
    });
    it('titik uji awal memang di luar radius 5 km (5,1 km)', async () => {
      const { distanceKm } = await import('../../src/lib/geo.js');
      const edge = distanceKm(-6.2, 106.8, -6.2088, 106.8456);
      expect(edge).toBeGreaterThan(5.0);
      expect(edge).toBeLessThan(5.3);
    });

    it('giveaway belum mulai -> giveaway_not_started', async () => {
      s.g3 = await mkGiveaway(api, s.adm, { title: 'Besok', start: HOUR, end: 2 * HOUR, draw: 3 * HOUR });
      const c3 = await genCodes(api, s.adm, s.g3.giveaway_id, 1);
      expect((await redeem(api, s.bobTok, c3[0])).error).toBe('giveaway_not_started');
    });
    it('giveaway tanpa commit block ditolak -> giveaway_not_ready', async () => {
      const g4 = await one(
        `insert into giveaways(title, category, prize_name, prize_value_idr, start_at, end_at, draw_at, winner_count, seed_hash)
         values ('Tanpa Commit','tech','X',1, now()-interval '1 hour', now()+interval '1 hour', now()+interval '2 hours', 1, $1) returning id`,
        [sha('x')],
      );
      await su.query("insert into codes(giveaway_id, code) values ($1, 'NOCM-MITT-0001')", [g4.id]);
      expect((await redeem(api, s.bobTok, 'NOCM-MITT-0001')).error).toBe('giveaway_not_ready');
    });
    it('giveaway sudah lewat end_at -> giveaway_ended', async () => {
      const g = await one(
        `insert into giveaways(title, category, prize_name, prize_value_idr, start_at, end_at, draw_at, winner_count, seed_hash)
         values ('Lewat','tech','X',1, now()-interval '3 hours', now()-interval '1 hour', now()+interval '2 hours', 1, $1) returning id`,
        [sha('y')],
      );
      await su.query("insert into codes(giveaway_id, code) values ($1, 'ENDD-0000-0001')", [g.id]);
      const tok = (await login(api, 'weirdo1', 'Passw0rd!1')).token;
      expect((await redeem(api, tok, 'ENDD-0000-0001')).error).toBe('giveaway_ended');
    });
  });

  describe('5. Konkurensi', () => {
    it('dua pengguna memakai kode yang sama bersamaan: tepat satu berhasil', async () => {
      await register(api, 'carol1', 'carol@example.com', 'Passw0rd!1', 'Carol');
      await register(api, 'dave01', 'dave@example.com', 'Passw0rd!1', 'Dave');
      s.carol = (await login(api, 'carol1', 'Passw0rd!1')).token;
      s.dave = (await login(api, 'dave01', 'Passw0rd!1')).token;
      s.gc = await mkGiveaway(api, s.adm, { title: 'Race', winners: 1, maxTickets: 50 });
      s.raceCodes = await genCodes(api, s.adm, s.gc.giveaway_id, 30);
      const res = await Promise.all([s.carol, s.dave].map((t) => redeem(api, t, s.raceCodes[0])));
      expect(res.filter((x) => x.ok)).toHaveLength(1);
      expect(res.filter((x) => !x.ok && x.error === 'code_used')).toHaveLength(1);
    });
    it('12 pembelian paralel: semua berhasil, nomor tiket unik berurutan tanpa celah', async () => {
      s.toks = [];
      for (let i = 0; i < 12; i++) {
        const n = String(i).padStart(2, '0');
        await register(api, `racer${n}`, `racer${i}@example.com`, 'Passw0rd!1', `Racer ${i}`);
        s.toks.push((await login(api, `racer${n}`, 'Passw0rd!1')).token);
      }
      const res = await Promise.all(s.toks.map((t, i) => redeem(api, t, s.raceCodes[1 + i])));
      const nums = res.filter((x) => x.ok).map((x) => x.ticket.ticket_number).sort((a, b) => a - b);
      const total = (await one('select count(*)::int n from tickets where giveaway_id=$1', [s.gc.giveaway_id])).n;
      expect(nums).toHaveLength(12);
      const prior = total - 12;
      expect(nums).toEqual(Array.from({ length: 12 }, (_, i) => prior + 1 + i));
    });
    it('banyak request paralel satu pengguna: batas tiket tidak terlampaui', async () => {
      const g = await mkGiveaway(api, s.adm, { title: 'Limit Race', winners: 1, maxTickets: 2 });
      const cs = await genCodes(api, s.adm, g.giveaway_id, 8);
      await register(api, 'limiter1', 'limiter@example.com', 'Passw0rd!1', 'L');
      const tok = (await login(api, 'limiter1', 'Passw0rd!1')).token;
      const res = await Promise.all(cs.map((c) => redeem(api, tok, c)));
      expect(res.filter((x) => x.ok)).toHaveLength(2);
      expect((await one('select count(*)::int n from tickets where giveaway_id=$1', [g.giveaway_id])).n).toBe(2);
      expect((await one('select ticket_counter from giveaways where id=$1', [g.giveaway_id])).ticket_counter).toBe(2);
    });
    it('banyak kode dibuat paralel tidak bentrok (unik global)', async () => {
      const g = await mkGiveaway(api, s.adm, { title: 'Codes Race' });
      const rs = await Promise.all(Array.from({ length: 4 }, () => genCodes(api, s.adm, g.giveaway_id, 200)));
      const all = rs.flat();
      expect(all).toHaveLength(800);
      expect(new Set(all).size).toBe(800);
    });
  });
}
