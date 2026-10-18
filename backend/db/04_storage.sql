-- =====================================================================
-- Code2Ticket - 04_storage.sql
-- Bucket foto profil. Hanya untuk Supabase. Jalankan KEEMPAT (opsional,
-- setelah fitur foto profil dikerjakan).
--
-- CATATAN KEAMANAN (tuliskan sebagai batasan di laporan):
-- Karena tidak memakai Supabase Auth, aplikasi mengunggah dengan anon key,
-- sehingga policy storage tidak bisa membatasi unggahan per pengguna.
-- Mitigasi: bucket dibatasi ukuran dan tipe file; nama file memakai UUID
-- pengguna; URL foto disimpan lewat rpc_update_profile yang bertoken.
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 512000, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy "avatars_public_read" on storage.objects
  for select to anon, authenticated using (bucket_id = 'avatars');

create policy "avatars_anon_insert" on storage.objects
  for insert to anon, authenticated with check (bucket_id = 'avatars');

create policy "avatars_anon_update" on storage.objects
  for update to anon, authenticated
  using (bucket_id = 'avatars') with check (bucket_id = 'avatars');
