-- =====================================================================
-- Code2Ticket - 07_user_photos.sql
-- Foto profil pengguna (JPEG, maks. 200 KB di database; API membatasi 150 KB).
-- Jalankan SETELAH 01_schema.sql dan 06_backend.sql (Supabase SQL Editor / psql).
-- Aman dijalankan ulang.
-- =====================================================================
create table if not exists public.user_photos (
  user_id      uuid primary key references public.users(id) on delete cascade,
  content_type text not null check (content_type = 'image/jpeg'),
  bytes        bytea not null check (octet_length(bytes) between 1 and 200000),
  updated_at   timestamptz not null default now()
);

-- Sama seperti tabel lain: tertutup untuk anon/authenticated; hanya backend (pemilik tabel) yang mengakses.
alter table public.user_photos enable row level security;
revoke all on public.user_photos from public, anon, authenticated;
