-- =====================================================================
-- Code2Ticket - 10_redeem_geo_restricted.sql
-- Pembatasan lokasi tukar kode pindah dari level KODE ke level GIVEAWAY (semua peserta satu giveaway diperlakukan sama).
-- Jalankan SETELAH 01, 06, 07, 08, dan 09 (Supabase SQL Editor / psql).
-- Aditif dan idempotent: aman dijalankan ulang. Tidak ada backfill: semua baris lama = false (tidak dibatasi).
--
-- Pembatasan memakai latitude, longitude, dan radius_km giveaway yang sudah ada.
-- Kolom codes.geo_lat / geo_lng / geo_radius_km DEPRECATED: tidak di-drop, tidak dibaca dan tidak ditulis lagi oleh backend baru.
-- Data produksi: bila ada giveaway yang kodenya sudah punya geo_* (mis. dari demo-seed lama), giveaway itu TIDAK otomatis
-- menjadi redeem_geo_restricted = true. Backend baru mengabaikan geo_* per kode, jadi giveaway tersebut tidak lagi dibatasi
-- sampai admin mengubahnya (bila belum ada tiket terbit) atau membuat giveaway baru dengan saklar menyala.
-- Cek (hanya baca): select distinct giveaway_id from public.codes where geo_radius_km is not null;
--
-- URUTAN DEPLOY (jangan dibalik):
--   1. Jalankan file ini di Supabase SQL Editor. Backend lama tetap jalan (tidak menyentuh kolom baru; masih memakai geo per kode).
--   2. Deploy backend baru ke Render (git push oleh pemilik repo).
--   3. Baru bangun dan pasang APK baru.
--   Backend lama + file ini belum dijalankan tidak bisa dipakai APK baru: APK baru mengirim redeem_geo_restricted dan backend
--   lama mengabaikannya (giveaway dibuat tanpa batas lokasi, tanpa crash).
--   APK lama + backend baru: field tambahan di JSON diabaikan, tidak crash; form Admin APK lama tidak punya saklar (selalu false),
--   dan pesan galat out_of_area memakai teks lama.
-- =====================================================================

alter table public.giveaways add column if not exists redeem_geo_restricted boolean not null default false;

do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.giveaways'::regclass and conname = 'giveaways_redeem_geo_complete') then
    alter table public.giveaways add constraint giveaways_redeem_geo_complete
      check (not redeem_geo_restricted or (latitude is not null and longitude is not null and radius_km is not null and radius_km > 0));
  end if;
end $$;

comment on column public.giveaways.redeem_geo_restricted is 'true = kode hanya bisa ditukar dalam radius_km dari (latitude, longitude) giveaway. Wajib terisi ketiganya, radius > 0.';
comment on column public.codes.geo_lat is 'DEPRECATED (10_redeem_geo_restricted.sql): tidak dipakai lagi. Pembatasan lokasi ada di giveaways.redeem_geo_restricted.';
comment on column public.codes.geo_lng is 'DEPRECATED (10_redeem_geo_restricted.sql): tidak dipakai lagi.';
comment on column public.codes.geo_radius_km is 'DEPRECATED (10_redeem_geo_restricted.sql): tidak dipakai lagi.';
