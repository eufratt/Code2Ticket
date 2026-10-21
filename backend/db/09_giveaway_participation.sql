-- =====================================================================
-- Code2Ticket - 09_giveaway_participation.sql
-- Info "cara mendapatkan kode" dan tautan penyelenggara pada giveaway.
-- Jalankan SETELAH 01, 06, 07, dan 08 (Supabase SQL Editor / psql).
-- Aditif dan idempotent: aman dijalankan ulang. Data lama tetap NULL (tanpa backfill).
--
-- URUTAN DEPLOY (jangan dibalik):
--   1. Jalankan file ini di Supabase SQL Editor. Backend lama tetap jalan (tidak menyentuh kolom baru).
--   2. Deploy backend baru ke Render (git push oleh pemilik repo). Giveaway baru wajib punya how_to_participate.
--   3. Baru bangun dan pasang APK baru.
--   APK lama + backend baru: field tambahan di JSON diabaikan, tidak crash; form Admin APK lama TIDAK bisa
--   membuat giveaway (how_to_participate wajib -> invalid_input) sampai APK baru dipasang.
-- =====================================================================

alter table public.giveaways add column if not exists how_to_participate text;
alter table public.giveaways add column if not exists organizer_url text;

do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.giveaways'::regclass and conname = 'giveaways_how_to_participate_len') then
    alter table public.giveaways add constraint giveaways_how_to_participate_len
      check (how_to_participate is null or char_length(how_to_participate) <= 2000);
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.giveaways'::regclass and conname = 'giveaways_organizer_url_len') then
    alter table public.giveaways add constraint giveaways_organizer_url_len
      check (organizer_url is null or char_length(organizer_url) <= 500);
  end if;
end $$;

comment on column public.giveaways.how_to_participate is 'Cara mendapatkan kode dari penyelenggara (teks bebas, maks. 2000 karakter). NULL untuk giveaway lama.';
comment on column public.giveaways.organizer_url is 'Tautan https opsional ke halaman penyelenggara (maks. 500 karakter). Divalidasi backend dan diperiksa lagi di app.';
