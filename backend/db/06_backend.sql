-- =====================================================================
-- Code2Ticket - 06_backend.sql
-- Migrasi arsitektur: Flutter -> backend Express -> Postgres.
-- Jalankan SETELAH 01_schema.sql. 02_functions.sql dan 03_cron.sql TIDAK
-- dipakai lagi (logic pindah ke Node.js); bila sudah terlanjur dijalankan,
-- file ini membuangnya. Aman dijalankan ulang.
--
-- Backend harus terhubung sebagai pemilik tabel (mis. role postgres): RLS
-- tetap aktif dan tanpa policy, jadi role lain tidak melihat baris apa pun.
-- =====================================================================

-- 1. Buang semua fungsi rpc_* dan fn_* (logic ada di backend).
--    trg_draw_chain_immutable (trigger append-only) sengaja dipertahankan.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and (p.proname like 'rpc\_%' or p.proname like 'fn\_%')
  loop
    execute format('drop function if exists %s cascade', f.sig);
  end loop;
end $$;

-- 2. Cabut SEMUA hak anon/authenticated. Aplikasi tidak lagi mengakses
--    Supabase/PostgREST langsung; hanya backend yang membaca/menulis.
drop policy if exists giveaways_public_read  on public.giveaways;
drop policy if exists draw_chain_public_read on public.draw_chain;

revoke all on all tables    in schema public from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on schema public from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke all on tables    from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on functions from public, anon, authenticated;

-- 3. Pastikan RLS aktif di semua tabel (sabuk pengaman; tanpa policy = tertutup).
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end $$;
