-- =====================================================================
-- Code2Ticket - 01_schema.sql
-- Tabel, constraint, index, dan hak akses (Supabase PostgreSQL).
-- Jalankan PERTAMA di SQL Editor Supabase (sebagai role postgres).
-- Aman dijalankan ulang pada database kosong; bukan skrip migrasi.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Ekstensi dan hak default
-- ---------------------------------------------------------------------
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_trgm  with schema extensions;

-- Semua objek baru di schema public TIDAK dapat diakses role anon/authenticated
-- secara otomatis. Akses diberikan eksplisit (lihat bagian 4 dan 02_functions.sql).
alter default privileges for role postgres in schema public
  revoke all on tables    from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 1. Konfigurasi dan log internal (tidak dapat diakses dari aplikasi)
-- ---------------------------------------------------------------------
create table public.app_config (
  key   text primary key,
  value text not null
);
comment on table public.app_config is
  'Konfigurasi server. demo_draw_enabled = tombol Run Draw (mode demo); fake_salt_key = kunci salt palsu agar username tidak dapat dienumerasi.';

insert into public.app_config(key, value) values
  ('demo_draw_enabled', 'true'),
  ('fake_salt_key', encode(extensions.gen_random_bytes(32), 'hex'));

create table public.system_events (
  id         bigint generated always as identity primary key,
  level      text not null check (level in ('info','warn','error')),
  event      text not null,
  details    jsonb,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2. Pengguna dan sesi
-- ---------------------------------------------------------------------
create table public.users (
  id            uuid primary key default gen_random_uuid(),
  username      text not null check (username ~ '^[A-Za-z0-9_]{4,20}$'),
  email         text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  full_name     text not null check (char_length(full_name) between 1 and 100),
  -- salt dibuat di aplikasi; password_hash = bcrypt(hash_dari_aplikasi) di server
  salt          text not null check (char_length(salt) between 16 and 128),
  password_hash text not null,
  photo_url     text,
  role          text not null default 'user' check (role in ('user','admin')),
  xp            integer not null default 0 check (xp >= 0),
  level         integer generated always as (xp / 500 + 1) stored,
  created_at    timestamptz not null default now()
);
create unique index users_username_uq on public.users (lower(username));
create unique index users_email_uq    on public.users (lower(email));

create table public.sessions (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.users(id) on delete cascade,
  token_hash   text not null unique,          -- SHA-256 dari token; token asli tidak disimpan
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  last_seen_at timestamptz,
  is_valid     boolean not null default true
);
create index sessions_user_idx on public.sessions (user_id);

create table public.login_attempts (
  identifier      text primary key,           -- username/email huruf kecil
  failed_count    integer not null default 0,
  locked_until    timestamptz,
  last_attempt_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. Giveaway, kode, tiket
-- ---------------------------------------------------------------------
create table public.giveaways (
  id                   uuid primary key default gen_random_uuid(),
  title                text not null check (char_length(title) between 1 and 120),
  description          text not null default '',
  organizer            text not null default '',
  category             text not null check (category in ('tech','gaming','travel','fashion','food','lifestyle','other')),
  prize_name           text not null,
  prize_value_usd      numeric(12,2) not null check (prize_value_usd >= 0),
  latitude             double precision check (latitude  between -90  and 90),
  longitude            double precision check (longitude between -180 and 180),
  address              text,
  radius_km            numeric(8,2) check (radius_km > 0),
  start_at             timestamptz not null,
  end_at               timestamptz not null,
  draw_at              timestamptz not null,
  winner_count         integer not null check (winner_count between 1 and 100),
  max_tickets_per_user integer not null default 10 check (max_tickets_per_user >= 1),
  ticket_counter       integer not null default 0,   -- nomor tiket terakhir (diperbarui di bawah kunci baris)
  seed_hash            text not null check (seed_hash ~ '^[0-9a-f]{64}$'),
  status               text not null default 'upcoming'
                         check (status in ('upcoming','active','waiting_draw','drawn')),
  created_by           uuid references public.users(id),
  created_at           timestamptz not null default now(),
  constraint giveaways_time_order check (start_at < end_at and end_at <= draw_at)
);
create index giveaways_status_draw_idx on public.giveaways (status, draw_at);
create index giveaways_category_idx    on public.giveaways (category);
create index giveaways_title_trgm      on public.giveaways using gin (title       extensions.gin_trgm_ops);
create index giveaways_prize_trgm      on public.giveaways using gin (prize_name  extensions.gin_trgm_ops);
create index giveaways_org_trgm        on public.giveaways using gin (organizer   extensions.gin_trgm_ops);

-- Seed rahasia untuk commit-reveal. TIDAK dapat dibaca dari aplikasi.
create table public.giveaway_secrets (
  giveaway_id uuid primary key references public.giveaways(id) on delete cascade,
  seed        text not null check (seed ~ '^[0-9a-f]{64}$'),
  created_at  timestamptz not null default now()
);

create table public.codes (
  id             uuid primary key default gen_random_uuid(),
  giveaway_id    uuid not null references public.giveaways(id) on delete cascade,
  code           text not null unique check (code ~ '^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$'),
  is_used        boolean not null default false,
  used_by        uuid references public.users(id),
  used_at        timestamptz,
  geo_lat        double precision,
  geo_lng        double precision,
  geo_radius_km  numeric(8,2),                       -- null = tidak dibatasi lokasi
  created_at     timestamptz not null default now(),
  constraint codes_geo_complete check (
    (geo_radius_km is null and geo_lat is null and geo_lng is null)
    or (geo_radius_km is not null and geo_lat is not null and geo_lng is not null and geo_radius_km > 0)
  ),
  constraint codes_used_consistent check (
    (is_used = false and used_by is null and used_at is null)
    or (is_used = true and used_by is not null and used_at is not null)
  )
);
create index codes_giveaway_idx on public.codes (giveaway_id);

create table public.code_attempts (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references public.users(id) on delete cascade,
  attempted_at timestamptz not null default now(),
  success      boolean not null,
  reason       text
);
create index code_attempts_user_idx on public.code_attempts (user_id, attempted_at desc);

create table public.tickets (
  id            uuid primary key default gen_random_uuid(),
  giveaway_id   uuid not null references public.giveaways(id) on delete cascade,
  ticket_number integer not null check (ticket_number > 0),
  user_id       uuid not null references public.users(id) on delete cascade,
  code_id       uuid not null unique references public.codes(id),
  created_at    timestamptz not null default now(),
  unique (giveaway_id, ticket_number)
);
create index tickets_user_idx     on public.tickets (user_id, created_at desc);
create index tickets_giveaway_idx on public.tickets (giveaway_id, user_id);

-- ---------------------------------------------------------------------
-- 4. Draw, pemenang, blockchain sederhana
-- ---------------------------------------------------------------------
create table public.draws (
  id            uuid primary key default gen_random_uuid(),
  giveaway_id   uuid not null unique references public.giveaways(id) on delete cascade,
  total_tickets integer not null check (total_tickets >= 0),
  trigger_type  text not null check (trigger_type in ('scheduler','admin_demo')),
  status        text not null check (status in ('completed','no_participants')),
  executed_at   timestamptz not null default now()
);

create table public.winners (
  id          uuid primary key default gen_random_uuid(),
  draw_id     uuid not null references public.draws(id) on delete cascade,
  giveaway_id uuid not null references public.giveaways(id) on delete cascade,
  ticket_id   uuid not null unique references public.tickets(id),
  user_id     uuid not null references public.users(id),
  rank        integer not null check (rank >= 1),
  unique (draw_id, rank),
  unique (draw_id, user_id)                           -- satu pengguna menang maksimal sekali per giveaway
);

-- Rantai blok. block_type = 'commit' (saat giveaway dibuat) atau 'result' (saat draw).
-- Rumus block_hash dan kontrak hashing ada di db/README.md dan fn_block_hash().
create table public.draw_chain (
  id              bigint generated always as identity primary key,
  block_index     integer not null unique check (block_index >= 1),
  block_type      text not null check (block_type in ('commit','result')),
  giveaway_id     uuid not null references public.giveaways(id),
  draw_id         uuid references public.draws(id),
  seed_hash       text,                               -- commit block
  seed            text,                               -- result block (dibuka)
  winner_count    integer,                            -- commit block
  total_tickets   integer,                            -- result block
  tickets_hash    text,                               -- result block
  winning_tickets text,                               -- result block: nomor tiket pemenang berurutan, dipisah koma
  ts_ms           bigint not null,                    -- timestamp (epoch milidetik, UTC)
  previous_hash   text not null check (previous_hash ~ '^[0-9a-f]{64}$'),
  block_hash      text not null unique check (block_hash ~ '^[0-9a-f]{64}$'),
  constraint draw_chain_commit_fields check (
    block_type <> 'commit' or (seed_hash is not null and winner_count is not null
      and seed is null and draw_id is null and total_tickets is null
      and tickets_hash is null and winning_tickets is null)
  ),
  constraint draw_chain_result_fields check (
    block_type <> 'result' or (seed is not null and draw_id is not null and total_tickets is not null
      and tickets_hash is not null and winning_tickets is not null
      and seed_hash is null and winner_count is null)
  )
);
-- Satu commit block dan satu result block per giveaway
create unique index draw_chain_one_commit_uq on public.draw_chain (giveaway_id) where block_type = 'commit';
create unique index draw_chain_one_result_uq on public.draw_chain (giveaway_id) where block_type = 'result';

-- Rantai bersifat append-only
create function public.trg_draw_chain_immutable() returns trigger
language plpgsql as $$
begin
  raise exception 'draw_chain bersifat append-only (% ditolak)', tg_op using errcode = '42501';
end $$;

create trigger draw_chain_no_update_delete
  before update or delete on public.draw_chain
  for each row execute function public.trg_draw_chain_immutable();
create trigger draw_chain_no_truncate
  before truncate on public.draw_chain
  for each statement execute function public.trg_draw_chain_immutable();

-- ---------------------------------------------------------------------
-- 5. Notifikasi, aktivitas, game, badge, feedback
-- ---------------------------------------------------------------------
create table public.notifications (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.users(id) on delete cascade,
  type        text not null check (type in ('ticket_created','draw_result','winner','reminder','info')),
  title       text not null,
  body        text not null,
  giveaway_id uuid references public.giveaways(id) on delete set null,
  is_read     boolean not null default false,
  created_at  timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, id desc);

create table public.user_activity (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references public.users(id) on delete cascade,
  activity_type text not null check (activity_type in ('view_giveaway','search','redeem_code','ticket_created','game_played','chat')),
  giveaway_id   uuid references public.giveaways(id) on delete set null,
  category      text,
  created_at    timestamptz not null default now()
);
create index user_activity_user_idx on public.user_activity (user_id, created_at desc);

create table public.game_scores (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references public.users(id) on delete cascade,
  score        integer not null check (score >= 0),
  stars        integer not null check (stars >= 0),
  cleared      boolean not null default false,
  xp_earned    integer not null default 0 check (xp_earned >= 0),
  duration_sec integer not null check (duration_sec between 0 and 600),
  created_at   timestamptz not null default now()
);
create index game_scores_user_idx    on public.game_scores (user_id, created_at desc);
create index game_scores_created_idx on public.game_scores (created_at desc);

create table public.user_badges (
  user_id    uuid not null references public.users(id) on delete cascade,
  badge_code text not null check (badge_code in ('first_ticket','ten_tickets','first_maze_clear','maze_master','early_bird')),
  earned_at  timestamptz not null default now(),
  primary key (user_id, badge_code)
);

create table public.feedback (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.users(id) on delete cascade,
  suggestion text not null check (char_length(suggestion) between 1 and 1000),
  impression text not null check (char_length(impression) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index feedback_user_idx on public.feedback (user_id, created_at desc);

-- ---------------------------------------------------------------------
-- 6. Hak akses
--    Prinsip: semua tabel tertutup untuk role anon/authenticated.
--    Pengecualian (data publik, hanya SELECT): giveaways dan draw_chain.
--    Semua operasi lain lewat fungsi RPC (02_functions.sql).
-- ---------------------------------------------------------------------
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end $$;

grant usage on schema public to anon, authenticated;

-- Supabase memberi hak default ke anon/authenticated pada objek baru; cabut semuanya
-- secara eksplisit (sabuk pengaman selain alter default privileges di atas).
revoke all on all tables    in schema public from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;

grant select on public.giveaways  to anon, authenticated;
grant select on public.draw_chain to anon, authenticated;

create policy giveaways_public_read  on public.giveaways
  for select to anon, authenticated using (true);
create policy draw_chain_public_read on public.draw_chain
  for select to anon, authenticated using (true);
