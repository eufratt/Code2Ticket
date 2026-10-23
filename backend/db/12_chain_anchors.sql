-- =====================================================================
-- Code2Ticket - 12_chain_anchors.sql
-- Jangkar (anchor) hash blok draw_chain ke blockchain publik testnet (Ethereum Sepolia secara bawaan).
-- Jalankan SETELAH 01 dan 11. Aditif dan idempotent: aman dijalankan ulang.
--
-- draw_chain TIDAK diubah (tetap append-only). Tabel ini hanya catatan pengiriman: satu baris per blok,
-- berisi hash transaksi yang membawa data "C2T:" + block_hash. Bukti sebenarnya ada di blockchain publik;
-- aplikasi membandingkannya langsung lewat RPC publik, bukan lewat tabel ini.
--
-- Redeem dan draw TIDAK bergantung pada tabel ini: backend menulis baris pending di dalam savepoint,
-- jadi bila tabel belum ada atau penulisan gagal, pembuatan giveaway dan draw tetap berhasil.
--
-- URUTAN DEPLOY: (1) file ini di Supabase SQL Editor, (2) env ANCHOR_* di Render, (3) git push backend, (4) APK baru.
-- Backend baru sebelum file ini dijalankan: jangkar dilewati (tercatat di log), GET /giveaways/:id/anchors
-- menjawab semua blok "none" (Belum dijangkarkan).
-- =====================================================================

create table if not exists public.chain_anchors (
  id               bigint generated always as identity primary key,
  chain_block_id   bigint not null unique references public.draw_chain(id),
  block_hash       text not null check (block_hash ~ '^[0-9a-f]{64}$'),
  chain_id         integer not null check (chain_id > 0),
  tx_hash          text check (tx_hash ~ '^0x[0-9a-f]{64}$'),
  nonce            bigint check (nonce >= 0),               -- nonce transaksi tx_hash; dipakai untuk mendeteksi tx yang hilang
  status           text not null default 'pending' check (status in ('pending','confirmed','failed')),
  attempts         integer not null default 0 check (attempts >= 0),
  last_error       text,                                    -- sudah disensor (tanpa kunci/URL RPC), maks. 300 karakter
  next_attempt_at  timestamptz not null default now(),      -- backoff percobaan ulang
  anchored_at      timestamptz,                             -- kapan transaksi terakhir dikirim
  confirmed_at     timestamptz,
  created_at       timestamptz not null default now(),
  constraint chain_anchors_confirmed check (status <> 'confirmed' or (tx_hash is not null and confirmed_at is not null))
);
create index if not exists chain_anchors_due_idx on public.chain_anchors (next_attempt_at) where status <> 'confirmed';

-- Sama seperti tabel lain: RLS aktif tanpa policy (hanya backend sebagai pemilik tabel yang membaca/menulis).
alter table public.chain_anchors enable row level security;
