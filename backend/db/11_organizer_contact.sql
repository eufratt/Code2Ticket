-- =====================================================================
-- Code2Ticket - 11_organizer_contact.sql
-- Kontak admin untuk penyelenggara yang ingin membuat giveaway (layar "Untuk Penyelenggara" di app).
-- Jalankan SETELAH 01 (tabel app_config). Aditif dan idempotent: aman dijalankan ulang, tidak menimpa nilai yang sudah diisi.
--
-- File ini HANYA menyisipkan dua baris kosong. Repo ini publik, jadi alamat email TIDAK boleh ditulis di sini.
-- Isi nilainya sendiri lewat Supabase SQL Editor (ganti placeholder):
--   update public.app_config set value = '<alamat-email-admin>' where key = 'organizer_contact_email';
--   update public.app_config set value = '<catatan singkat, opsional, maks. 300 karakter>' where key = 'organizer_contact_note';
-- Mengosongkan lagi (tombol hubungi hilang dari app):
--   update public.app_config set value = '' where key in ('organizer_contact_email', 'organizer_contact_note');
-- Backend memvalidasi sebelum mengirim: email format valid maks. 254 karakter, catatan maks. 300 karakter;
-- nilai tidak valid diperlakukan sebagai kosong. Hanya dua kunci ini yang dibaca endpoint GET /app-config/organizer.
--
-- URUTAN DEPLOY (jangan dibalik):
--   1. Jalankan file ini di Supabase SQL Editor. Backend lama tetap jalan (tidak menyentuh kunci baru).
--   2. Isi nilai email lewat `update` di atas.
--   3. Deploy backend baru ke Render (git push oleh pemilik repo).
--   4. Baru bangun dan pasang APK baru.
--   Urutan terbalik tidak menyebabkan crash:
--   - Backend baru sebelum file ini dijalankan: baris tidak ada -> endpoint menjawab kontak kosong.
--   - Baris ada tetapi nilai belum diisi: kontak kosong.
--   - APK baru + backend lama: GET /app-config/organizer menjawab 404; app menampilkan "Kontak admin belum tersedia. Coba lagi nanti."
--     tanpa tombol, panduan tetap tampil.
-- =====================================================================

insert into public.app_config(key, value) values
  ('organizer_contact_email', ''),
  ('organizer_contact_note', '')
on conflict (key) do nothing;
