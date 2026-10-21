-- =====================================================================
-- Code2Ticket - 08_prize_value_idr.sql
-- Nilai hadiah giveaway: mata uang dasar berpindah dari USD ke Rupiah.
-- Kolom baru prize_value_idr (rupiah bulat, tanpa desimal) menggantikan prize_value_usd.
-- Jalankan SETELAH 01_schema.sql, 06_backend.sql, dan 07_user_photos.sql
-- (Supabase SQL Editor / psql). Aditif dan idempotent: aman dijalankan ulang.
--
-- URUTAN DEPLOY (jangan dibalik):
--   1. Jalankan file ini di Supabase SQL Editor. Backend lama tetap jalan: ia masih membaca/menulis
--      prize_value_usd, yang tidak dihapus di sini.
--   2. Deploy backend baru ke Render. Backend baru hanya memakai prize_value_idr.
--   3. Baru bangun dan pasang APK baru (membaca field prize_value_idr).
--   Bila ada giveaway dibuat lewat backend LAMA setelah langkah 1 (prize_value_idr = 0, prize_value_usd > 0),
--   jalankan file ini sekali lagi setelah langkah 2: backfill hanya menyentuh baris yang masih 0.
--
-- DEPRECATED: prize_value_usd tidak dipakai lagi oleh kode. Kolom dipertahankan sementara
-- (rollback / audit) dan boleh di-drop di migrasi berikutnya setelah semua klien memakai prize_value_idr.
-- =====================================================================

-- 1. Kolom baru: rupiah bulat, 0..100.000.000.000.
alter table public.giveaways
  add column if not exists prize_value_idr numeric(16,0) not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.giveaways'::regclass and conname = 'giveaways_prize_value_idr_range'
  ) then
    alter table public.giveaways
      add constraint giveaways_prize_value_idr_range
      check (prize_value_idr >= 0 and prize_value_idr <= 100000000000);
  end if;
end $$;

-- 2. Kolom lama tidak lagi diisi kode baru, jadi tidak boleh NOT NULL (insert tanpa kolom ini harus lolos).
alter table public.giveaways alter column prize_value_usd drop not null;

-- 3. Backfill baris lama (hanya data uji): kurs tetap 18.000 IDR/USD, dibulatkan ke ribuan, dibatasi batas atas.
--    Hanya baris yang belum punya nilai IDR, sehingga nilai yang sudah diisi admin tidak tertimpa saat dijalankan ulang.
update public.giveaways
   set prize_value_idr = least(round(prize_value_usd * 18000, -3), 100000000000)
 where prize_value_idr = 0 and prize_value_usd is not null and prize_value_usd > 0;

comment on column public.giveaways.prize_value_idr is 'Nilai hadiah dalam rupiah bulat (mata uang dasar). Aplikasi mengonversi ke mata uang pilihan pengguna.';
comment on column public.giveaways.prize_value_usd is 'DEPRECATED: tidak dipakai lagi; digantikan prize_value_idr. Akan di-drop di migrasi berikutnya.';
