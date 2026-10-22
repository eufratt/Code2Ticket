import fs from 'node:fs';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ORGANIZER_CONTACT_SQL, createContext, makeApi } from './helpers.js';

// Kontak penyelenggara (migrasi 11, GET /app-config/organizer).
const real = {};
const api = makeApi(() => real.app);
const set = (key, value) => real.su.query('update app_config set value=$2 where key=$1', [key, value]);
const get = () => api.get('/app-config/organizer');

beforeAll(async () => {
  Object.assign(real, await createContext('organizer_contact'));
}, 60_000);
afterAll(() => real.close());

describe('GET /app-config/organizer', () => {
  it('migrasi menyisipkan baris kosong -> tanpa kontak, tanpa session', async () => {
    expect(await get()).toEqual({ ok: true, email: null, note: null });
  });

  it('nilai valid dikirim (di-trim) dan tidak membocorkan kunci app_config lain', async () => {
    await set('organizer_contact_email', '  admin@example.test  ');
    await set('organizer_contact_note', 'Dibalas dalam 2 hari kerja.');
    const r = await get();
    expect(r).toEqual({ ok: true, email: 'admin@example.test', note: 'Dibalas dalam 2 hari kerja.' });
    const json = JSON.stringify(r);
    for (const k of ['demo_draw_enabled', 'fake_salt_key']) expect(json).not.toContain(k);
    const salt = (await real.su.query("select value from app_config where key='fake_salt_key'")).rows[0].value;
    expect(json).not.toContain(salt);
  });

  it.each([
    ['tanpa @', 'bukan-email'], ['tanpa domain', 'a@b'], ['spasi', 'a b@example.test'], ['dua @', 'a@@example.test'],
    ['kontrol', 'a@example.test\u0001'], ['terlalu panjang', `${'a'.repeat(250)}@example.test`], ['kosong', '   '],
  ])('email tidak valid (%s) dianggap kosong', async (_n, v) => {
    await set('organizer_contact_email', v);
    expect((await get()).email).toBeNull();
  });

  it('email tepat 254 karakter diterima', async () => {
    const e = `${'a'.repeat(254 - '@example.test'.length)}@example.test`;
    expect(e).toHaveLength(254);
    await set('organizer_contact_email', e);
    expect((await get()).email).toBe(e);
  });

  it('catatan: 300 karakter diterima, 301 atau berkarakter kontrol dibuang (bukan dipotong)', async () => {
    await set('organizer_contact_note', 'x'.repeat(300));
    expect((await get()).note).toHaveLength(300);
    await set('organizer_contact_note', 'x'.repeat(301));
    expect((await get()).note).toBeNull();
    await set('organizer_contact_note', 'baris\u0007satu');
    expect((await get()).note).toBeNull();
  });

  it('baris dihapus (migrasi belum jalan) -> kosong, bukan galat', async () => {
    await real.su.query("delete from app_config where key like 'organizer_contact_%'");
    expect(await get()).toEqual({ ok: true, email: null, note: null });
  });

  it('anon tidak bisa membaca app_config langsung', async () => {
    await expect(real.anon.query('select * from public.app_config')).rejects.toMatchObject({ code: '42501' });
  });
});

describe('migrasi 11', () => {
  const sql = fs.readFileSync(ORGANIZER_CONTACT_SQL, 'utf8');

  it('idempotent: dijalankan ulang tidak menimpa nilai yang sudah diisi dan tidak menggandakan baris', async () => {
    await real.su.query(sql); // mengembalikan baris yang dihapus tes sebelumnya
    await set('organizer_contact_email', 'admin@example.test');
    await real.su.query(sql);
    await real.su.query(sql);
    const rows = (await real.su.query("select key, value from app_config where key like 'organizer_contact_%' order by key")).rows;
    expect(rows).toEqual([
      { key: 'organizer_contact_email', value: 'admin@example.test' },
      { key: 'organizer_contact_note', value: '' },
    ]);
  });

  it('tidak berisi data pribadi: tanpa alamat email, nomor telepon, atau tautan', () => {
    expect(sql).not.toMatch(/[\w.+-]+@[\w-]+\.[\w.-]+/);
    expect(sql).not.toMatch(/\+?\d[\d\s-]{8,}\d/);
    expect(sql).not.toMatch(/https?:\/\//);
    // nilai yang disisipkan hanya string kosong
    const inserted = sql.match(/insert into[\s\S]*?on conflict/i)[0];
    expect(inserted.match(/\('organizer_contact_\w+', ''\)/g)).toHaveLength(2);
  });
});
