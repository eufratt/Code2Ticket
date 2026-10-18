import { describe, expect, it } from 'vitest';
import { genCodes, login, mkGiveaway, redeem, register } from '../helpers.js';

// Bagian 6 (search), 10 (game, feedback, profil, aktivitas), 11 (hak akses role anon).
export function searchSection(ctx) {
  const { api, s } = ctx;

  describe('6. Search', () => {
    it('search default: hanya giveaway aktif', async () => {
      await mkGiveaway(api, s.adm, { title: 'Gaming Mouse Giveaway', category: 'gaming', lat: -6.9175, lng: 107.6191, winners: 1 }); // Bandung
      const r = await api.get('/giveaways');
      expect(r.length).toBeGreaterThanOrEqual(4);
      expect(r.every((x) => x.status !== 'drawn')).toBe(true);
      expect(Object.keys(r[0]).sort()).toEqual([
        'address', 'category', 'description', 'distance_km', 'draw_at', 'end_at', 'id', 'latitude', 'longitude', 'organizer',
        'prize_name', 'prize_value_usd', 'radius_km', 'start_at', 'status', 'ticket_count', 'title', 'winner_count',
      ]);
      expect(typeof r[0].prize_value_usd).toBe('number');
    });
    it('search kata kunci', async () => {
      const r = await api.get('/giveaways', { query: { q: 'gaming' } });
      expect(r).toHaveLength(1);
      expect(r[0].title.startsWith('Gaming')).toBe(true);
    });
    it('search kata kunci di nama hadiah dan penyelenggara', async () => {
      expect((await api.get('/giveaways', { query: { q: 'lapto' } })).length).toBeGreaterThan(1);
      expect((await api.get('/giveaways', { query: { q: 'acme' } })).length).toBeGreaterThan(1);
    });
    it('filter kategori', async () => {
      const r = await api.get('/giveaways', { query: { category: 'travel' } });
      expect(r).toHaveLength(1);
      expect(r[0].category).toBe('travel');
    });
    it('filter nilai hadiah', async () => {
      expect(await api.get('/giveaways', { query: { min_value: 501 } })).toEqual([]);
      expect((await api.get('/giveaways', { query: { min_value: 500, max_value: 500 } })).length).toBeGreaterThan(0);
    });
    it('filter radius 10 km dari Jakarta tidak memuat Bandung', async () => {
      const r = await api.get('/giveaways', { query: { lat: -6.2, lng: 106.8, radius_km: 10, sort: 'nearest' } });
      expect(r.length).toBeGreaterThan(0);
      expect(r.every((x) => x.distance_km <= 10)).toBe(true);
      expect(r.some((x) => x.category === 'gaming')).toBe(false);
    });
    it('sort terdekat menaik, tanpa koordinat di urutan akhir', async () => {
      const r = await api.get('/giveaways', { query: { lat: -6.2, lng: 106.8, sort: 'nearest' } });
      const d = r.map((x) => x.distance_km);
      const known = d.filter((x) => x !== null);
      expect(known).toEqual([...known].sort((a, b) => a - b));
      expect(d).toEqual([...known, ...Array(d.length - known.length).fill(null)]);
    });
    it('paginasi tidak tumpang tindih', async () => {
      const a = await api.get('/giveaways', { query: { limit: 2, offset: 0 } });
      const b = await api.get('/giveaways', { query: { limit: 2, offset: 2 } });
      expect(a).toHaveLength(2);
      expect(b.some((x) => a.some((y) => y.id === x.id))).toBe(false);
    });
    it('limit dibatasi 50 dan minimal 1', async () => {
      expect((await api.get('/giveaways', { query: { limit: 0 } })).length).toBe(1);
      expect((await api.get('/giveaways', { query: { limit: 1000 } })).length).toBeLessThanOrEqual(50);
    });
    it('karakter wildcard di-escape', async () => {
      expect(await api.get('/giveaways', { query: { q: '100%' } })).toEqual([]);
      expect(await api.get('/giveaways', { query: { q: '_' } })).toEqual([]);
    });
    it('filter upcoming', async () => {
      const r = await api.get('/giveaways', { query: { status: 'upcoming' } });
      expect(r).toHaveLength(1);
      expect(r[0].title).toBe('Besok');
    });
    it('filter finished memuat yang sudah di-draw / lewat end_at', async () => {
      const r = await api.get('/giveaways', { query: { status: 'finished' } });
      expect(r.some((x) => x.title === 'Lewat')).toBe(true);
    });
    it('deadline_days membatasi end_at', async () => {
      expect(await api.get('/giveaways', { query: { deadline_days: 0 } })).toEqual([]);
      expect((await api.get('/giveaways', { query: { deadline_days: 7 } })).length).toBeGreaterThan(0);
    });
    it('parameter tidak valid -> invalid_input (bukan 500)', async () => {
      const r = await api.raw('get', '/giveaways', { query: { min_value: 'abc' } });
      expect(r.status).toBe(200);
      expect(r.body.error).toBe('invalid_input');
    });
    it('winners / verification: id tidak valid dan tidak ada', async () => {
      expect((await api.get('/giveaways/bukan-uuid/winners')).error).toBe('invalid_input');
      expect((await api.get('/giveaways/00000000-0000-4000-8000-000000000000/winners')).error).toBe('not_found');
      expect((await api.get('/giveaways/00000000-0000-4000-8000-000000000000/verification')).error).toBe('not_found');
    });
    it('winners sebelum draw -> drawn:false', async () => {
      expect(await api.get(`/giveaways/${s.gid1}/winners`)).toEqual({ ok: true, drawn: false, winners: [] });
    });
  });
}

export function featureSection(ctx) {
  const { api, su, s } = ctx;
  const one = async (sql, params) => (await su.query(sql, params)).rows[0];

  describe('10. Game, feedback, profil, aktivitas', () => {
    const score = (stars, left, cleared, dur) => api.post('/game/scores', { token: s.aliceTok, body: { stars, seconds_left: left, cleared, duration_sec: dur } });
    it('skor game: XP = bintang*10 + sisa waktu', async () => {
      const r = await score(5, 30, true, 40);
      expect(r.ok).toBe(true);
      expect(r.xp_earned).toBe(80);
      expect(r.user.xp).toBe(80);
      expect(r.score).toBe(5 * 100 + 30 * 10);
      expect(r.user.badges).toContain('first_maze_clear');
    });
    it('batas XP harian 200', async () => {
      const r = await score(30, 60, true, 20);
      expect(r.xp_earned).toBe(120);
      expect(r.daily_xp_total).toBe(200);
      expect(r.daily_cap_reached).toBe(true);
    });
    it('setelah batas harian XP tidak bertambah', async () => {
      const r = await score(10, 10, true, 20);
      expect(r.xp_earned).toBe(0);
      expect(r.user.xp).toBe(200);
    });
    it('sisa waktu tidak dihitung bila tidak clear', async () => {
      const r = await score(1, 50, false, 20);
      expect(r.score).toBe(100);
    });
    it('input game tidak valid ditolak', async () => {
      expect((await score(99, 10, true, 20)).error).toBe('invalid_input');
      expect((await score('5', 10, true, 20)).error).toBe('invalid_input');
    });
    it('level = xp/500 + 1', async () => {
      expect((await api.get('/auth/me', { token: s.aliceTok })).user.level).toBe(1);
      await su.query("update users set xp = 1000 where username='alice'");
      expect((await api.get('/auth/me', { token: s.aliceTok })).user.level).toBe(3);
      await su.query("update users set xp = 200 where username='alice'");
    });
    it('leaderboard', async () => {
      const lb = await api.get('/game/leaderboard', { token: s.aliceTok });
      expect(lb).toHaveLength(1);
      expect(lb[0]).toMatchObject({ username: 'alice', rank: 1 });
      expect(Object.keys(lb[0]).sort()).toEqual(['level', 'rank', 'total_score', 'username']);
    });
    it('leaderboard butuh session', async () => {
      expect((await api.raw('get', '/game/leaderboard', { token: '0'.repeat(64) })).status).toBe(401);
    });

    it('feedback kosong ditolak', async () => {
      expect((await api.post('/feedback', { token: s.aliceTok, body: { suggestion: '  ', impression: 'ok' } })).field).toBe('suggestion');
    });
    it('feedback > 1000 karakter ditolak', async () => {
      expect((await api.post('/feedback', { token: s.aliceTok, body: { suggestion: 'x'.repeat(1001), impression: 'ok' } })).field).toBe('suggestion');
    });
    it('feedback tersimpan', async () => {
      expect((await api.post('/feedback', { token: s.aliceTok, body: { suggestion: 'Tambah materi sensor', impression: 'Seru' } })).ok).toBe(true);
    });
    it('riwayat feedback', async () => {
      const r = await api.get('/feedback', { token: s.aliceTok });
      expect(r).toHaveLength(1);
      expect(Object.keys(r[0]).sort()).toEqual(['created_at', 'id', 'impression', 'suggestion']);
    });
    it('update profil', async () => {
      const r = await api.patch('/me', { token: s.aliceTok, body: { full_name: 'Alice Baru', photo_url: 'https://example.com/a.jpg' } });
      expect(r.ok).toBe(true);
      expect(r.user.full_name).toBe('Alice Baru');
      expect(r.user.photo_url.endsWith('a.jpg')).toBe(true);
    });
    it('update profil: nama kosong / foto terlalu panjang ditolak; foto tidak terhapus bila tidak dikirim', async () => {
      expect((await api.patch('/me', { token: s.aliceTok, body: { full_name: '   ' } })).field).toBe('full_name');
      expect((await api.patch('/me', { token: s.aliceTok, body: { photo_url: 'x'.repeat(501) } })).field).toBe('photo_url');
      const r = await api.patch('/me', { token: s.aliceTok, body: {} });
      expect(r.user.full_name).toBe('Alice Baru');
      expect(r.user.photo_url.endsWith('a.jpg')).toBe(true);
    });
    it('log aktivitas valid', async () => {
      expect((await api.post('/activity', { token: s.aliceTok, body: { type: 'view_giveaway', giveaway_id: s.gid1, category: 'tech' } })).ok).toBe(true);
    });
    it('log aktivitas dengan tipe server-only ditolak', async () => {
      expect((await api.post('/activity', { token: s.aliceTok, body: { type: 'ticket_created', giveaway_id: s.gid1, category: 'tech' } })).error).toBe('invalid_input');
    });
    it('log aktivitas dengan giveaway tidak ada -> tersimpan dengan giveaway null', async () => {
      const r = await api.post('/activity', { token: s.aliceTok, body: { type: 'search', giveaway_id: '00000000-0000-4000-8000-000000000000' } });
      expect(r.ok).toBe(true);
    });
    it('afinitas kategori: tiket*3 + lihat*1', async () => {
      const n = (await one("select count(*)::int n from tickets t join giveaways g on g.id=t.giveaway_id join users u on u.id=t.user_id where u.username='alice' and g.category='tech'")).n;
      expect(n).toBe(6); // 3 Tech Prize + 3 Multi
      expect((await api.get('/me/affinity', { token: s.aliceTok })).tech).toBe(6 * 3 + 1);
    });
    it('polling notifikasi: hanya yang lebih baru dari after_id', async () => {
      const ns = await api.get('/notifications', { token: s.aliceTok });
      const firstId = ns[ns.length - 1].id;
      const newer = await api.get('/notifications', { token: s.aliceTok, query: { after_id: firstId } });
      expect(newer.every((n) => n.id > firstId)).toBe(true);
      expect(newer).toHaveLength(ns.length - 1);
    });
    it('tandai semua notifikasi dibaca', async () => {
      const r = await api.post('/notifications/read', { token: s.aliceTok, body: {} });
      expect(r.ok).toBe(true);
      expect(r.updated).toBeGreaterThanOrEqual(1);
      expect((await api.get('/notifications', { token: s.aliceTok })).every((n) => n.is_read)).toBe(true);
    });
    it('tandai sebagian notifikasi dibaca', async () => {
      await register(api, 'notif01', 'notif@example.com', 'Passw0rd!1', 'N');
      const tok = (await login(api, 'notif01', 'Passw0rd!1')).token;
      const g = await mkGiveaway(api, s.adm, { title: 'Notif Test' });
      for (const c of await genCodes(api, s.adm, g.giveaway_id, 2)) await redeem(api, tok, c);
      const ns = await api.get('/notifications', { token: tok });
      expect(ns).toHaveLength(2);
      const r = await api.post('/notifications/read', { token: tok, body: { ids: [ns[0].id] } });
      expect(r.updated).toBe(1);
      const after = await api.get('/notifications', { token: tok });
      expect(after.filter((n) => n.is_read)).toHaveLength(1);
    });
    it('notifikasi milik user lain tidak terlihat', async () => {
      const mine = new Set((await api.get('/notifications', { token: s.aliceTok })).map((n) => n.id));
      const bobs = (await api.get('/notifications', { token: s.bobTok })).map((n) => n.id);
      expect(bobs.some((id) => mine.has(id))).toBe(false);
    });
  });
}

export function accessSection(ctx) {
  const { anon, su } = ctx;
  const denied = async (sql) => {
    try {
      await anon.query(sql);
    } catch (e) {
      return e.code === '42501';
    }
    return false;
  };

  describe('11. Hak akses role anon', () => {
    const tables = ['users', 'sessions', 'login_attempts', 'giveaways', 'giveaway_secrets', 'codes', 'code_attempts', 'tickets',
      'draws', 'winners', 'draw_chain', 'notifications', 'user_activity', 'game_scores', 'user_badges', 'feedback', 'app_config', 'system_events'];
    for (const t of tables) {
      it(`anon tidak bisa SELECT ${t}`, async () => {
        expect(await denied(`select * from public.${t} limit 1`)).toBe(true);
      });
    }
    it('anon tidak bisa UPDATE giveaways', async () => {
      expect(await denied("update public.giveaways set title='x'")).toBe(true);
    });
    it('anon tidak bisa INSERT tickets', async () => {
      expect(await denied('insert into public.tickets(giveaway_id, ticket_number, user_id, code_id) values (gen_random_uuid(),1,gen_random_uuid(),gen_random_uuid())')).toBe(true);
    });
    it('anon tidak bisa DELETE draw_chain', async () => {
      expect(await denied('delete from public.draw_chain')).toBe(true);
    });
    it('anon tidak bisa INSERT winners', async () => {
      expect(await denied('insert into public.winners(draw_id, giveaway_id, ticket_id, user_id, rank) values (gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),1)')).toBe(true);
    });
    it('anon tidak bisa memakai schema public', async () => {
      expect(await denied('select 1 from public.giveaways')).toBe(true);
    });
    it('semua fungsi rpc_* / fn_* sudah dibuang; trigger append-only dipertahankan', async () => {
      const gone = await su.query("select count(*)::int n from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname like 'rpc\\_%' or p.proname like 'fn\\_%')");
      expect(gone.rows[0].n).toBe(0);
      const trg = await su.query("select count(*)::int n from pg_trigger where tgrelid='public.draw_chain'::regclass and not tgisinternal");
      expect(trg.rows[0].n).toBe(2);
    });
    it('tidak ada hak tabel tersisa untuk anon/authenticated', async () => {
      const r = await su.query(
        `select count(*)::int n from information_schema.role_table_grants
          where table_schema='public' and grantee in ('anon','authenticated','PUBLIC')`,
      );
      expect(r.rows[0].n).toBe(0);
    });
    it('RLS aktif di semua tabel public', async () => {
      const r = await su.query("select count(*)::int n from pg_tables where schemaname='public' and not rowsecurity");
      expect(r.rows[0].n).toBe(0);
    });
  });
}
