import { describe, expect, it } from 'vitest';
import { verifyChain } from '../../src/lib/chain.js';
import {
  blockHash, genCodes, HOUR, mkGiveaway, pickWinners, redeem, sha, verify,
} from '../helpers.js';

export function drawSections(ctx) {
  const { api, su, s, real } = ctx;
  const one = async (sql, params) => (await su.query(sql, params)).rows[0];
  const count = async (sql, params) => (await one(sql, params)).n;
  const runDraw = (tok, gid) => api.post(`/admin/giveaways/${gid}/draw`, { token: tok });
  const verification = (gid) => api.get(`/giveaways/${gid}/verification`);

  describe('7. Draw demo (admin) dan verifikasi independen', () => {
    it('racer00 memiliki banyak tiket (kasus satu pengguna satu hadiah)', async () => {
      await api.post('/admin/giveaways', { token: s.adm, body: { id: s.gc.giveaway_id, title: 'Race' } });
      const more = await genCodes(api, s.adm, s.gc.giveaway_id, 6);
      for (const c of more) await redeem(api, s.toks[0], c);
      expect(await count(
        "select count(*)::int n from tickets t join users u on u.id=t.user_id where t.giveaway_id=$1 and u.username='racer00'",
        [s.gc.giveaway_id],
      )).toBeGreaterThanOrEqual(7);
    });
    it('non-admin tidak bisa run draw (403)', async () => {
      const r = await api.raw('post', `/admin/giveaways/${s.gc.giveaway_id}/draw`, { token: s.aliceTok });
      expect(r.status).toBe(403);
    });
    it('admin menjalankan draw demo', async () => {
      const r = await runDraw(s.adm, s.gc.giveaway_id);
      expect(r.ok).toBe(true);
      expect(r.status).toBe('completed');
      expect(r.winning_tickets).toHaveLength(1);
    });
    it('draw tercatat trigger admin_demo', async () => {
      expect((await one('select trigger_type from draws where giveaway_id=$1', [s.gc.giveaway_id])).trigger_type).toBe('admin_demo');
    });
    it('draw kedua ditolak (idempotent)', async () => {
      expect((await runDraw(s.adm, s.gc.giveaway_id)).error).toBe('already_drawn');
    });
    it('hanya satu draw dan satu result block', async () => {
      expect(await count('select count(*)::int n from draws where giveaway_id=$1', [s.gc.giveaway_id])).toBe(1);
      expect(await count("select count(*)::int n from draw_chain where giveaway_id=$1 and block_type='result'", [s.gc.giveaway_id])).toBe(1);
    });
    it('status giveaway = drawn', async () => {
      expect((await one('select status from giveaways where id=$1', [s.gc.giveaway_id])).status).toBe('drawn');
    });
    it('pemenang publik: nama tersamar', async () => {
      const w = await api.get(`/giveaways/${s.gc.giveaway_id}/winners`);
      expect(w.drawn).toBe(true);
      expect(w.winners).toHaveLength(1);
      expect(w.winners[0].name).toContain('***');
      expect(Object.keys(w.winners[0]).sort()).toEqual(['name', 'rank', 'ticket_number']);
    });
    it('verifikasi independen -> valid', async () => {
      s.vdRace = await verification(s.gc.giveaway_id);
      expect(verify(s.vdRace)).toEqual([true, 'valid']);
    });
    it('audit rantai server (verifyChain) semua ok', async () => {
      const rows = await verifyChain(su);
      expect(rows.length).toBeGreaterThan(0);
      expect(rows.every((r) => r.ok)).toBe(true);
    });
    it('daftar tiket tidak membuka user_id', () => {
      expect(s.vdRace.tickets.every((t) => t.length === 2 && t[1].length === 12)).toBe(true);
    });

    it('draw 5 pemenang dari 10 peserta', async () => {
      s.gm = await mkGiveaway(api, s.adm, { title: 'Multi', winners: 5, maxTickets: 10 });
      const cm = await genCodes(api, s.adm, s.gm.giveaway_id, 40);
      s.cm = cm;
      let k = 0;
      for (const tok of [s.aliceTok, s.bobTok, s.carol, s.dave, ...s.toks.slice(0, 6)]) {
        for (let i = 0; i < 3; i++) await redeem(api, tok, cm[k++]);
      }
      s.multi = await runDraw(s.adm, s.gm.giveaway_id);
      expect(s.multi.ok).toBe(true);
      expect(s.multi.winning_tickets).toHaveLength(5);
    });
    it('pemenang semua pengguna berbeda', async () => {
      const wu = (await su.query('select user_id from winners where giveaway_id=$1', [s.gm.giveaway_id])).rows;
      expect(new Set(wu.map((x) => x.user_id)).size).toBe(5);
    });
    it('verifikasi independen draw multi-pemenang valid', async () => {
      s.vdMulti = await verification(s.gm.giveaway_id);
      expect(verify(s.vdMulti)).toEqual([true, 'valid']);
    });
    it('hasil implementasi uji = hasil API', () => {
      const rb = s.vdMulti.chain.find((b) => b.block_type === 'result' && b.giveaway_id === s.gm.giveaway_id);
      const [, win] = pickWinners(rb.seed, s.gm.giveaway_id, s.vdMulti.tickets, 5);
      expect(win).toEqual(s.multi.winning_tickets);
    });
    it('status tiket setelah draw: winner / not_selected', async () => {
      for (const tok of [s.aliceTok, s.bobTok]) {
        const mine = (await api.get('/tickets', { token: tok })).filter((t) => t.giveaway_id === s.gm.giveaway_id);
        expect(mine.every((t) => ['winner', 'not_selected'].includes(t.result))).toBe(true);
      }
    });
    it('notifikasi: 5 pemenang dan 5 peserta lain', async () => {
      const nw = await count("select count(*)::int n from notifications where giveaway_id=$1 and type='winner'", [s.gm.giveaway_id]);
      const nr = await count("select count(*)::int n from notifications where giveaway_id=$1 and type='draw_result'", [s.gm.giveaway_id]);
      expect([nw, nr]).toEqual([5, 5]);
    });
    it('format pesan notifikasi pemenang', async () => {
      const n = await one("select body from notifications where giveaway_id=$1 and type='winner' limit 1", [s.gm.giveaway_id]);
      expect(n.body).toMatch(/^Tiket #\d{6} memenangkan Laptop pada undian Multi\.$/);
    });
    it('setelah draw, input kode ditolak', async () => {
      expect(['giveaway_ended', 'code_used']).toContain((await redeem(api, s.aliceTok, s.cm[39])).error);
    });
    it('system_events draw_completed tercatat', async () => {
      expect(await count("select count(*)::int n from system_events where event='draw_completed'")).toBeGreaterThanOrEqual(2);
    });

    it('satu peserta, 3 tiket, 5 hadiah -> hanya 1 pemenang', async () => {
      const gl = await mkGiveaway(api, s.adm, { title: 'Sedikit', winners: 5, maxTickets: 10 });
      for (const c of await genCodes(api, s.adm, gl.giveaway_id, 3)) await redeem(api, s.carol, c);
      const r = await runDraw(s.adm, gl.giveaway_id);
      expect(r.ok).toBe(true);
      expect(r.winning_tickets).toHaveLength(1);
      expect(verify(await verification(gl.giveaway_id))[0]).toBe(true);
    });
    it('draw tanpa tiket -> no_participants, tanpa error', async () => {
      const ge = await mkGiveaway(api, s.adm, { title: 'Kosong', winners: 2 });
      const r = await runDraw(s.adm, ge.giveaway_id);
      expect(r.ok).toBe(true);
      expect(r.status).toBe('no_participants');
      expect(r.winning_tickets).toEqual([]);
      expect(verify(await verification(ge.giveaway_id))[0]).toBe(true);
    });
    it('draw demo pada giveaway belum mulai ditolak', async () => {
      expect((await runDraw(s.adm, s.g3.giveaway_id)).error).toBe('not_started');
    });
    it('flag demo dimatikan -> demo_disabled', async () => {
      await su.query("update app_config set value='false' where key='demo_draw_enabled'");
      expect((await runDraw(s.adm, s.g3.giveaway_id)).error).toBe('demo_disabled');
      await su.query("update app_config set value='true' where key='demo_draw_enabled'");
    });
    it('draw giveaway yang tidak ada -> not_found', async () => {
      expect((await runDraw(s.adm, '00000000-0000-4000-8000-000000000000')).error).toBe('not_found');
    });
    it('verifikasi sebelum draw: hanya commit block, tickets null', async () => {
      const v = await verification(s.gid1);
      expect(v.tickets).toBeNull();
      expect(v.chain.find((b) => b.giveaway_id === s.gid1 && b.block_type === 'result')).toBeUndefined();
      expect(verify(v)[0]).toBe(true);
    });
    it('draw paralel pada giveaway sama: tepat satu berhasil', async () => {
      const g = await mkGiveaway(api, s.adm, { title: 'Dua Draw', winners: 1 });
      for (const c of await genCodes(api, s.adm, g.giveaway_id, 2)) await redeem(api, s.dave, c);
      const rs = await Promise.all([1, 2, 3].map(() => runDraw(s.adm, g.giveaway_id)));
      expect(rs.filter((x) => x.ok)).toHaveLength(1);
      expect(rs.filter((x) => x.error === 'already_drawn')).toHaveLength(2);
      expect(await count('select count(*)::int n from draws where giveaway_id=$1', [g.giveaway_id])).toBe(1);
      expect(verify(await verification(g.giveaway_id))[0]).toBe(true);
    });
    it('draw beberapa giveaway paralel: rantai tetap berurutan dan valid', async () => {
      const gs = [];
      for (let i = 0; i < 4; i++) gs.push(await mkGiveaway(api, s.adm, { title: `Par ${i}`, winners: 1 }));
      await Promise.all(gs.map((g) => runDraw(s.adm, g.giveaway_id)));
      const rows = await verifyChain(su);
      expect(rows.every((r) => r.ok)).toBe(true);
      const idx = (await su.query('select block_index from draw_chain order by block_index')).rows.map((r) => r.block_index);
      expect(idx).toEqual(idx.map((_, i) => i + 1));
    });
  });

  describe('8. Keamanan commit-reveal dan manipulasi', () => {
    it('seed diganti sebelum draw -> draw ditolak (seed_mismatch)', async () => {
      s.gt = await mkGiveaway(api, s.adm, { title: 'Tamper', winners: 1 });
      const ct = await genCodes(api, s.adm, s.gt.giveaway_id, 4);
      for (const c of ct.slice(0, 3)) await redeem(api, s.dave, c);
      await su.query('update giveaway_secrets set seed = $1 where giveaway_id=$2', [sha('lain'), s.gt.giveaway_id]);
      expect((await runDraw(s.adm, s.gt.giveaway_id)).error).toBe('seed_mismatch');
    });
    it('status giveaway tidak berubah dan tidak ada pemenang', async () => {
      expect((await one('select status from giveaways where id=$1', [s.gt.giveaway_id])).status).not.toBe('drawn');
      expect(await count('select count(*)::int n from winners where giveaway_id=$1', [s.gt.giveaway_id])).toBe(0);
      expect(await count('select count(*)::int n from draws where giveaway_id=$1', [s.gt.giveaway_id])).toBe(0);
      expect(await count("select count(*)::int n from draw_chain where giveaway_id=$1 and block_type='result'", [s.gt.giveaway_id])).toBe(0);
    });
    it('kejadian error tercatat', async () => {
      expect(await count("select count(*)::int n from system_events where event='draw_seed_mismatch'")).toBe(1);
    });

    it('sebelum manipulasi valid', async () => {
      s.vdBefore = await verification(s.gc.giveaway_id);
      expect(verify(s.vdBefore)[0]).toBe(true);
    });
    it('hasil diubah -> verifikasi mendeteksi; audit server mendeteksi', async () => {
      await su.query('alter table draw_chain disable trigger draw_chain_no_update_delete');
      await su.query("update draw_chain set winning_tickets = '999' where giveaway_id=$1 and block_type='result'", [s.gc.giveaway_id]);
      const [okk] = verify(await verification(s.gc.giveaway_id));
      expect(okk).toBe(false);
      expect((await verifyChain(su)).filter((r) => !r.ok).length).toBeGreaterThanOrEqual(1);
    });
    it('seed palsu dengan hash dihitung ulang tetap terdeteksi', async () => {
      const rb = s.vdBefore.chain.find((b) => b.block_type === 'result' && b.giveaway_id === s.gc.giveaway_id);
      await su.query('update draw_chain set winning_tickets = $1 where giveaway_id=$2 and block_type=$3', [rb.winning_tickets, s.gc.giveaway_id, 'result']);
      const forged = JSON.parse(JSON.stringify(s.vdBefore));
      const fb = forged.chain.find((b) => b.block_index === rb.block_index);
      fb.seed = sha('palsu');
      fb.block_hash = blockHash(fb);
      expect(verify(forged)[0]).toBe(false);
    });
    it('setelah dipulihkan valid kembali', async () => {
      await su.query('alter table draw_chain enable trigger draw_chain_no_update_delete');
      expect(verify(await verification(s.gc.giveaway_id))[0]).toBe(true);
    });
    it('commit setelah tiket pertama terdeteksi', () => {
      const forged = JSON.parse(JSON.stringify(s.vdBefore));
      forged.first_ticket_ms = 1;
      const [okk, why] = verify(forged);
      expect(okk).toBe(false);
      expect(why).toContain('commit');
    });
  });

  describe('9. Scheduler', () => {
    it('sebelum jatuh tempo: scheduler tidak menjalankan draw giveaway ini', async () => {
      const { runDueDraws } = await import('../../src/services/draw.js');
      s.gs = await mkGiveaway(api, s.adm, { title: 'Auto', winners: 1, start: -HOUR, end: 3000, draw: 4000 });
      s.gtick = await mkGiveaway(api, s.adm, { title: 'Auto Tick', winners: 1, start: -HOUR, end: 3000, draw: 4000 });
      for (const gid of [s.gs.giveaway_id, s.gtick.giveaway_id]) {
        for (const c of await genCodes(api, s.adm, gid, 3)) await redeem(api, s.carol, c);
      }
      await runDueDraws(real.pool);
      expect((await one('select status from giveaways where id=$1', [s.gs.giveaway_id])).status).not.toBe('drawn');
    });
    it('POST /internal/tick: tanpa/rahasia salah ditolak', async () => {
      expect((await api.raw('post', '/internal/tick')).status).toBe(403);
      expect((await api.raw('post', '/internal/tick', { headers: { 'X-Tick-Secret': 'salah' } })).status).toBe(403);
    });
    it('POST /internal/tick: dimatikan bila TICK_SECRET kosong', async () => {
      const { createApp } = await import('../../src/app.js');
      const off = createApp({ pool: real.pool, config: { ...real.config, TICK_SECRET: '' }, log: () => {} });
      const { call } = await import('../helpers.js');
      expect((await call(off, 'post', '/internal/tick', { headers: { 'X-Tick-Secret': '' } })).status).toBe(404);
    });
    it('setelah jatuh tempo: runDueDraws menjalankan draw otomatis', async () => {
      const { runDueDraws } = await import('../../src/services/draw.js');
      await new Promise((r) => setTimeout(r, 4500));
      const n = await runDueDraws(real.pool);
      expect(n).toBeGreaterThanOrEqual(1);
      expect((await one('select trigger_type from draws where giveaway_id=$1', [s.gs.giveaway_id])).trigger_type).toBe('scheduler');
    });
    it('dijalankan lagi: tidak ada draw ganda', async () => {
      const { runDueDraws } = await import('../../src/services/draw.js');
      expect(await runDueDraws(real.pool)).toBe(0);
    });
    it('hasil scheduler lolos verifikasi', async () => {
      expect(verify(await verification(s.gs.giveaway_id))[0]).toBe(true);
    });
    it('POST /internal/tick dengan rahasia benar menjalankan draw jatuh tempo', async () => {
      // gtick sudah ikut terundi oleh runDueDraws di atas (keduanya jatuh tempo); buat satu lagi yang tepat jatuh tempo.
      const g = await mkGiveaway(api, s.adm, { title: 'Auto Tick 2', winners: 1, start: -HOUR, end: 1500, draw: 2000 });
      for (const c of await genCodes(api, s.adm, g.giveaway_id, 2)) await redeem(api, s.carol, c);
      await new Promise((r) => setTimeout(r, 2300));
      const r = await api.post('/internal/tick', { headers: { 'X-Tick-Secret': real.config.TICK_SECRET } });
      expect(r).toEqual({ ok: true, drawn: 1 });
      expect((await one('select trigger_type from draws where giveaway_id=$1', [g.giveaway_id])).trigger_type).toBe('scheduler');
      expect(verify(await verification(g.giveaway_id))[0]).toBe(true);
    });
    it('scheduler tidak menjalankan draw untuk draw_at di masa depan', async () => {
      const r = await api.post('/internal/tick', { headers: { 'X-Tick-Secret': real.config.TICK_SECRET } });
      expect(r.drawn).toBe(0);
    });
    it('status giveaway diperbarui scheduler', async () => {
      const { refreshGiveawayStatus } = await import('../../src/services/draw.js');
      await su.query("update giveaways set status='upcoming' where id=$1", [s.gid1]);
      expect(await refreshGiveawayStatus(real.pool)).toBeGreaterThanOrEqual(1);
      expect((await one('select status from giveaways where id=$1', [s.gid1])).status).toBe('active');
    });
    it('node-cron: startScheduler terdaftar dan dapat dihentikan', async () => {
      const cron = (await import('node-cron')).default;
      expect(cron.validate('* * * * *')).toBe(true);
      expect(cron.validate('0 20 * * *')).toBe(true);
      const { startScheduler } = await import('../../src/services/scheduler.js');
      const sch = startScheduler({ pool: real.pool });
      expect(typeof sch.stop).toBe('function');
      sch.stop();
    });
    it('cleanup membuang sesi/percobaan lama saja', async () => {
      const { cleanup } = await import('../../src/services/draw.js');
      await su.query("insert into login_attempts(identifier, last_attempt_at) values ('lama', now() - interval '2 days'), ('baru', now())");
      await cleanup(real.pool);
      expect(await count("select count(*)::int n from login_attempts where identifier='lama'")).toBe(0);
      expect(await count("select count(*)::int n from login_attempts where identifier='baru'")).toBe(1);
    });
  });
}
