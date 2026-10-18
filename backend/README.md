# Code2Ticket Backend

Flutter -> **Express** -> **Postgres** (`DATABASE_URL` langsung, tanpa Supabase client/anon key).
Seluruh logic fungsi SQL lama (`02_functions.sql`, `03_cron.sql`) ada di Node.js. Skema memakai
`01_schema.sql` apa adanya, ditambah migrasi `db/06_backend.sql`.

## Menjalankan

```bash
npm install
cp .env.example .env            # isi DATABASE_URL, TICK_SECRET, dst.
psql "$DATABASE_URL" -f db/01_schema.sql
psql "$DATABASE_URL" -f db/06_backend.sql
ADMIN_PASSWORD='...' npm run create-admin -- namamu email@kamu.com "Nama Lengkap"
npm start
```

- Postgres non-Supabase: jalankan dulu `db/00_supabase_shim.sql`
  (membuat role `anon`/`authenticated` dan schema `extensions` yang dirujuk `01_schema.sql`).
- Backend harus terhubung sebagai **pemilik tabel** (mis. `postgres`): RLS aktif tanpa policy.
- `02_functions.sql`, `03_cron.sql`, `05_bootstrap_admin.sql`, `make_admin_sql.py` tidak dipakai lagi
  (memanggil `rpc_*`). Pakai `npm run create-admin`.
- Scheduler: `node-cron` di dalam proses (`SCHEDULER_ENABLED=true`), atau matikan dan panggil
  `POST /internal/tick` dengan header `X-Tick-Secret` dari cron host. Aman dijalankan bersamaan
  (draw dikunci per baris giveaway dan idempotent).
- `npm run verify-chain` mengaudit seluruh hash-chain.

## Tes

Butuh Postgres dengan ekstensi `pgcrypto` dan `pg_trgm`, serta Python 3 (tes kontrak memuat
`test/reference/test_m1.py` sebagai implementasi acuan). Tiap file tes membuat database sendiri.

```bash
TEST_PG_URL=postgres://postgres@127.0.0.1:5432 npm test     # default 127.0.0.1:54329
```

## Konvensi respons

| Kasus | Respons |
|---|---|
| Berhasil | `200 {"ok":true,...}` |
| Gagal bisnis | `200 {"ok":false,"error":"<kode>",...}` (kode sama dengan SQL lama) |
| Session tidak valid / tanpa header | `401 {"ok":false,"error":"invalid_session"}` |
| Bukan admin | `403 {"ok":false,"error":"forbidden"}` |
| Terlalu banyak request | `429 {"ok":false,"error":"too_many_requests"}` |

Endpoint daftar/array (`GET /giveaways`, `/tickets`, `/notifications`, `/feedback`, `/game/leaderboard`,
`/admin/giveaways/:id/codes`) dan `/me/affinity` mengembalikan array/objek polos seperti hasil SQL lama.
Token dikirim lewat `Authorization: Bearer <token>`.

## Endpoint

| Endpoint | Auth | Pengganti |
|---|---|---|
| `POST /auth/register`, `/auth/salt`, `/auth/login` | - | `rpc_register`, `rpc_get_salt`, `rpc_login` |
| `POST /auth/logout` | token (tidak divalidasi) | `rpc_logout` |
| `GET /auth/me` | session | `rpc_validate_session` |
| `PATCH /me` | session | `rpc_update_profile` |
| `GET /giveaways` (`q,category,min_value,max_value,lat,lng,radius_km,deadline_days,status,sort,limit,offset`) | - | `rpc_search_giveaways` |
| `GET /giveaways/:id/winners`, `/giveaways/:id/verification` | - | `rpc_get_winners`, `rpc_get_verification_data` |
| `POST /codes/redeem` (`code,lat,lng`) | session | `rpc_redeem_code` |
| `GET /tickets` | session | `rpc_get_my_tickets` |
| `POST /activity` (`type,giveaway_id,category`) | session | `rpc_log_activity` |
| `GET /me/affinity` | session | `rpc_get_category_affinity` |
| `POST /game/scores` (`stars,seconds_left,cleared,duration_sec`), `GET /game/leaderboard?limit=` | session | `rpc_submit_game_score`, `rpc_get_leaderboard` |
| `GET /notifications?after_id=&limit=`, `POST /notifications/read` (`ids`) | session | `rpc_get_notifications`, `rpc_mark_notifications_read` |
| `POST /feedback` (`suggestion,impression`), `GET /feedback` | session | `rpc_submit_feedback`, `rpc_get_my_feedback` |
| `POST /admin/giveaways` (tanpa `id` = buat, dengan `id` = ubah) | admin | `rpc_admin_upsert_giveaway` |
| `POST /admin/giveaways/:id/codes` (`count,geo_lat,geo_lng,geo_radius_km`), `GET` daftar | admin | `rpc_admin_generate_codes`, `rpc_admin_list_codes` |
| `POST /admin/giveaways/:id/draw` | admin | `rpc_admin_run_draw` |
| `POST /internal/tick` | `X-Tick-Secret` | `fn_run_due_draws` |

Waktu pada `POST /admin/giveaways` (`start_at`, `end_at`, `draw_at`) wajib memakai zona (`Z` atau `+hh:mm`).
