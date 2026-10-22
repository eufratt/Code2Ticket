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
psql "$DATABASE_URL" -f db/07_user_photos.sql   # foto profil (Supabase: tempel di SQL Editor)
psql "$DATABASE_URL" -f db/08_prize_value_idr.sql   # nilai hadiah dalam rupiah (lihat "Nilai hadiah" di bawah)
psql "$DATABASE_URL" -f db/09_giveaway_participation.sql   # cara mendapatkan kode + tautan penyelenggara
psql "$DATABASE_URL" -f db/10_redeem_geo_restricted.sql     # batas lokasi tukar kode per giveaway
psql "$DATABASE_URL" -f db/11_organizer_contact.sql          # baris kontak admin untuk penyelenggara (kosong; lihat "Kontak penyelenggara")
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

## Nilai hadiah (rupiah)

- Mata uang dasar nilai hadiah adalah **rupiah bulat**: kolom `giveaways.prize_value_idr` (`numeric(16,0)`, `0..100.000.000.000`), field API `prize_value_idr` (angka bulat).
  `prize_value_usd` sudah **deprecated**: tidak dibaca/ditulis kode, tidak ada di respons; kolom dibiarkan (nullable) sampai di-drop di migrasi berikutnya.
- `POST /admin/giveaways`: `prize_value_idr` wajib bilangan bulat `1..100.000.000.000` (JSON number); selain itu `invalid_input` dengan `field: "prize_value_idr"`. Saat mengubah (ada `id`), field opsional tetapi bila ada harus valid.
- `GET /giveaways`: `min_value` / `max_value` dan `sort=value` bekerja pada **rupiah** (klien mengonversi masukan pengguna ke IDR sebelum mengirim). Konversi ke mata uang lain hanya di aplikasi (Frankfurter).
- Konteks Asisten memuat `nilai_rupiah` (bukan `nilai_usd`).
- Migrasi `db/08_prize_value_idr.sql`: aditif dan idempotent; backfill baris lama `round(prize_value_usd * 18000, -3)` (kurs tetap, data uji). Urutan deploy: jalankan SQL -> deploy backend -> pasang APK baru.
  APK lama membaca `prize_value_usd` yang tidak ada lagi: nilai hadiah tampil "-" (tanpa crash), filter nilai di APK lama dianggap rupiah.

## Cara mendapatkan kode dan tautan penyelenggara

- Batas lokasi tukar kode ada di level GIVEAWAY: kolom `giveaways.redeem_geo_restricted` (boolean, bawaan false; CHECK: bila true, `latitude`, `longitude`, `radius_km` wajib terisi dan radius > 0; migrasi `db/10_redeem_geo_restricted.sql`, aditif, idempotent, tanpa backfill). `POST /codes/redeem` pada giveaway terbatas: tanpa lokasi `location_required`, di luar `radius_km` (haversine) `out_of_area`; lokasi tidak disimpan. `codes.geo_lat/geo_lng/geo_radius_km` DEPRECATED (tidak dibaca/ditulis). `POST /admin/giveaways` menerima `redeem_geo_restricted` (boolean, bawaan false; true tanpa koordinat+radius > 0 -> `invalid_input` field `redeem_geo_restricted`). Mengubah saklar atau lokasi/radius giveaway terbatas setelah ada tiket terbit -> `redeem_geo_locked`. `POST /admin/giveaways/:id/codes` menolak `geo_lat/geo_lng/geo_radius_km` (`invalid_input`, field `geo`); `GET` daftar kode tidak lagi berisi `geo_radius_km`. List/detail giveaway menyertakan `redeem_geo_restricted`.
- Kolom `giveaways.how_to_participate` (text, CHECK <= 2000, NULL untuk data lama) dan `organizer_url` (text, CHECK <= 500, NULL boleh); migrasi `db/09_giveaway_participation.sql` (aditif, idempotent, tanpa backfill).
- `POST /admin/giveaways` membuat: `how_to_participate` WAJIB, string 10..2000 karakter setelah trim (kalau tidak `invalid_input` + `field`). `organizer_url` opsional: absolut `https://` saja, maks. 500, tanpa `user:pass@`, spasi/karakter kontrol, host domain bertitik (IP dan `localhost` ditolak); nilai di-trim, `''`/`null` = tidak ada. Mengubah: field opsional; `organizer_url: null` mengosongkan.
- Payload: `GET /giveaways` (daftar, Discover, Peta) memuat `organizer_url` tetapi TIDAK `how_to_participate`; `GET /giveaways/:id` memuat keduanya.
- Asisten: DATA berisi `penyelenggara`, `cara_ikut` (dipotong 600 karakter) dan `tautan_penyelenggara`; prompt melarang mengarang cara atau tautan.
- Urutan deploy: jalankan SQL -> deploy backend -> pasang APK baru. APK lama + backend baru: tidak crash (field tambahan diabaikan) tetapi form Admin APK lama ditolak (`how_to_participate` wajib). APK baru + backend lama: detail memakai pesan pengganti, form Admin mengirim field tak dikenal yang diabaikan server lama.

## Perilaku yang perlu diketahui (M8a)

- **Status giveaway** (`status` di `GET /giveaways`, `GET /giveaways/:id`, `GET /tickets` > `giveaway_status`, dan konteks Asisten) dihitung dari waktu
  saat dibaca: `upcoming` / `active` / `waiting_draw`, `drawn` bila sudah diundi. Kolom `giveaways.status` hanya dipakai internal dan baru disegarkan scheduler.
- **Cakupan status `GET /giveaways` (Discover)**: tanpa `status` dan tanpa `q` = `active` + `upcoming`; tanpa `status` dengan `q` = semua status.
  `status` eksplisit dipatuhi persis: `active`, `upcoming`, `waiting_draw`, `drawn`, `finished` (= `waiting_draw` + `drawn`), `all`, atau
  beberapa dipisah koma (`active,upcoming`); nilai tak dikenal -> `invalid_input` field `status` (dulu diam-diam berarti semua).
  Hasil selalu dikelompokkan: aktif, akan datang, menunggu draw, selesai; di dalam kelompok mengikuti `sort`. `sort=deadline` (bawaan):
  aktif = `end_at` terdekat, akan datang = `start_at` terdekat, menunggu draw/selesai = `end_at` terbaru dulu. Paginasi tetap (`limit` bawaan 20,
  dijepit 1..50; `offset`) di atas urutan berkelompok itu. Endpoint tetap publik dan hanya memuat kolom publik yang sama (tidak ada giveaway
  non-publik di skema); `GET /admin/giveaways` tetap khusus admin, semua status, terbaru dulu tanpa kelompok.
  Home memanggil `GET /giveaways?status=active&limit=50` supaya tidak ikut berubah.
- **Draw terjadwal yang gagal `seed_mismatch`** dicoba sekali lalu dilewati scheduler (event `draw_seed_mismatch` di `system_events` dicatat sekali; `draw_chain` tidak disentuh).
  Draw manual admin tetap bisa dicoba. Setelah penyebabnya diperbaiki, buka lagi untuk scheduler dengan menghapus event itu:
  `delete from system_events where event = 'draw_seed_mismatch' and details->>'giveaway_id' = '<id>';`
- **Batas redeem**: hanya tebakan kode yang dihitung ke batas 5 kegagalan / 10 menit (`invalid_format`, `code_not_found`, `code_used` oleh orang lain). Alasan sah
  (`giveaway_not_started`, `giveaway_ended`, `giveaway_not_ready`, `ticket_limit`, `location_required`, `out_of_area`, kode yang sudah dipakai dirinya sendiri) tetap dicatat di
  `code_attempts` tetapi tidak dihitung. Kode galat ke klien tidak berubah. Kunci login 5 salah / 15 menit tidak berubah.
- **Pembersihan**: `login_attempts` (> 24 jam, bukan kunci aktif) dan `code_attempts` (> 1 hari) dibuang tiap jam oleh scheduler dan, karena Render gratis bisa tertidur,
  juga dari `POST /internal/tick` (maks. sekali per jam per proses). Cleanup harian untuk sesi tetap.
- **Salt**: `POST /auth/register` hanya menerima salt 32 hex huruf kecil (format yang dibuat app) sehingga sama dengan salt palsu (HMAC `fake_salt_key`) untuk identifier tak dikenal.
  Akun lama dengan format lain (hanya mungkin bila didaftarkan lewat klien lain) dapat dicari dengan `select id, username from users where salt !~ '^[0-9a-f]{32}$';`.

## Batas laju (rate limit) dan demo banyak perangkat

Batas dihitung per IP per menit (`express-rate-limit`). Default: `RATE_LIMIT_MAX=300` (semua endpoint), `AUTH_RATE_LIMIT_MAX=20` (semua `/auth/*`), `UPLOAD_RATE_LIMIT_MAX=10` (`PUT /me/photo`).
Catatan penting untuk demo (banyak ponsel di satu Wi-Fi = satu IP publik):
- **`TRUST_PROXY=1` wajib di Render.** Tanpa itu `req.ip` adalah IP proxy Render sehingga SEMUA pengguna berbagi satu bucket.
- Satu login memakai 2 permintaan `/auth/*` (`salt` + `login`), pembukaan app dengan sesi tersimpan 1 (`/auth/me`), dan pendaftaran 1. Dengan 20/menit, hanya ~10 ponsel yang bisa login bersamaan
  dari satu IP; sisanya mendapat 429 `too_many_requests`. Satu layar Home memakai ~5-8 permintaan, sehingga 300/menit kira-kira cukup untuk 40 ponsel yang aktif bersamaan (perkiraan, belum diukur).
- Perlindungan tebak password tidak bergantung pada batas IP ini (kunci per akun 5 salah / 15 menit, bcrypt), jadi menaikkan batas IP aman.
- Nilai yang disarankan untuk hari demo (env Render, kembalikan sesudahnya): `TRUST_PROXY=1`, `AUTH_RATE_LIMIT_MAX=120`, `RATE_LIMIT_MAX=1200`, `UPLOAD_RATE_LIMIT_MAX=30`.
  Default di kode tidak diubah. Batas `POST /chat` tidak memakai IP, melainkan per pengguna (`AI_RATE_PER_MINUTE`, `AI_DAILY_LIMIT_PER_USER`).

## Data demo

Membuat 5 giveaway aktif (gaming online tanpa batas lokasi, travel di Bali tanpa batas radius, kuliner di Surabaya dengan batas radius 15 km, smartphone di Jakarta Pusat dengan batas radius 10 km, serta sneaker di Jakarta Selatan dengan batas radius 12 km) dengan 10 kode tiap giveaway, lewat API (login admin + `POST /admin/giveaways` + `POST /admin/giveaways/:id/codes`). Kode hanya dicetak ke terminal. Akun harus admin (lihat `npm run create-admin`).

Script ini bersifat **idempotent**: jika dijalankan ulang, giveaway aktif yang sudah ada akan digunakan kembali (dan diperpanjang masa aktifnya jika mendekati akhir), serta kode yang belum terpakai akan dicetak ulang tanpa membuat duplikasi. Kode baru hanya dibuat jika sisa kode yang belum terpakai kurang dari 10. Kredensial tidak pernah ditulis ke file/repo.

PowerShell (kredensial hanya di sesi terminal ini):

```powershell
$env:API_BASE_URL = "https://code2ticket.onrender.com"
$env:ADMIN_USERNAME = "namamu"
$env:ADMIN_PASSWORD = Read-Host "Password admin"   # tidak ditulis ke file
npm run demo-seed
Remove-Item Env:ADMIN_PASSWORD
```

Server gratis Render bisa butuh sekitar 1 menit untuk bangun pada permintaan pertama.

## Asisten AI (`POST /chat`)

Asisten tab "Asisten" memanggil OpenAI Chat Completions dari server (fetch bawaan Node, tanpa SDK). Kunci tidak pernah dikirim ke klien.

Env (tanpa nilai bawaan untuk rahasia; lihat `.env.example`):

| Env | Arti |
|---|---|
| `OPENAI_API_KEY` | Kunci OpenAI. Kosong = fitur mati. Jangan commit; isi di env Render. |
| `OPENAI_MODEL` | Nama model, WAJIB diatur. Kosong -> `ai_not_configured`. |
| `AI_DAILY_LIMIT_PER_USER` | Kuota pesan per pengguna per hari Asia/Jakarta (bawaan 30). |
| `AI_DAILY_LIMIT_GLOBAL` | Kuota pesan SEMUA pengguna per hari UTC (bawaan 300), jawaban `global_limit`. Dihitung di memori proses: hilang saat restart, tidak dibagi antar instance, jadi hanya pagar biaya kasar. |
| `AI_RATE_PER_MINUTE` | Batas pesan per pengguna per menit (bawaan 8). |
| `OPENAI_TIMEOUT_MS` | Timeout panggilan OpenAI (bawaan 20000). |

Perilaku:
- Sukses: `{"ok":true,"reply":"...","related":[ringkasan giveaway aktif, maks. 3]}`. `related` = bentuk sama dengan item `GET /giveaways`, hanya giveaway aktif yang cocok kata kunci pesan.
- Galat (HTTP 200): `invalid_input` (+`field` `message`/`history`), `ai_not_configured`, `rate_limited` (+`retry_after_seconds`), `daily_limit`, `ai_unavailable` (rate limit/5xx/timeout/400 dari OpenAI; detail upstream tidak dibocorkan). Sesi tidak valid: 401.
- Panggilan memakai `max_completion_tokens: 400` dan tanpa `temperature`. Peran `system` hanya dari server; `history` dari klien hanya `user`/`assistant` (selain itu `invalid_input`).
- Konteks (RAG sederhana): sampai 5 giveaway aktif (kata kunci, lalu minat pengguna dari `/me/affinity`, lalu draw terdekat) dimasukkan ke prompt sebagai DATA; tanpa data pengguna lain.
- Log hanya `CHAT upstream status=<n> type=<jenis>` / `timeout` / `network`. Isi pesan, kunci, dan pesan galat upstream tidak dicatat. Aktivitas `chat` dicatat ke `user_activity` tanpa isi pesan.
- Batas pemakaian dihitung di MEMORI proses (tanpa perubahan skema): hilang saat server restart dan tidak dibagi antar instance. Cukup untuk satu instance Render; untuk beberapa instance butuh tabel (belum ada).

## Kontak penyelenggara

Penyelenggara yang ingin membuat giveaway menghubungi admin lewat email (layar "Untuk Penyelenggara" di app; tidak ada peran penyelenggara). Alamat TIDAK ada di repo (publik): hanya di tabel `app_config`, kunci `organizer_contact_email` dan `organizer_contact_note` (opsional). `db/11_organizer_contact.sql` hanya menyisipkan dua baris kosong (`on conflict do nothing`, idempotent). Isi lewat Supabase SQL Editor:

```sql
update public.app_config set value = '<alamat-email-admin>' where key = 'organizer_contact_email';
update public.app_config set value = '<catatan singkat, opsional>' where key = 'organizer_contact_note';
```

`GET /app-config/organizer` (publik, tanpa session, hanya limiter global) menjawab `{"ok":true,"email":<string|null>,"note":<string|null>}`. Hanya dua kunci itu yang dibaca (kunci lain, mis. `demo_draw_enabled`, tidak pernah dikirim). Validasi di server: email format valid maks. 254 karakter; catatan maks. 300 karakter tanpa karakter kontrol; nilai tidak valid, kosong, atau baris tidak ada = `null`.

Urutan deploy: (1) jalankan `11_organizer_contact.sql`, (2) isi nilai email lewat `update`, (3) push backend, (4) APK baru. Urutan terbalik tidak crash: backend baru sebelum migrasi/isi = kontak `null`; APK baru dengan backend lama (404) = "Kontak admin belum tersedia. Coba lagi nanti." tanpa tombol.

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
| `PUT /me/photo` (badan JPEG biner, `Content-Type: image/jpeg`, maks. 150 KB; 413 bila lebih besar; segmen APP1 (EXIF/GPS, XMP) dibuang sebelum disimpan, struktur JPEG rusak -> `invalid_input`) | session | (baru) |
| `GET /users/:id/photo` (publik, `Cache-Control` + `ETag`; 404 bila tidak ada) | - | (baru) |
| `GET /giveaways` (`q,category,min_value,max_value,lat,lng,radius_km,deadline_days,status,sort,limit,offset`; `offset` maks. 10000 dan `deadline_days` maks. 3650, nilai lebih besar dijepit; cakupan `status` bawaan lihat "Perilaku yang perlu diketahui") | - | `rpc_search_giveaways` |
| `GET /giveaways/:id` (404 `not_found` bila tidak ada) | - | (baru, tanpa padanan RPC) |
| `GET /app-config/organizer` (`{ok,email,note}`; hanya kunci `organizer_contact_email` / `organizer_contact_note`) | - | (baru) |
| `GET /giveaways/:id/winners`, `/giveaways/:id/verification` | - | `rpc_get_winners`, `rpc_get_verification_data` |
| `POST /codes/redeem` (`code,lat,lng`) | session | `rpc_redeem_code` |
| `GET /tickets` | session | `rpc_get_my_tickets` |
| `POST /activity` (`type,giveaway_id,category`) | session | `rpc_log_activity` |
| `GET /me/affinity` | session | `rpc_get_category_affinity` |
| `POST /game/scores` (`stars,seconds_left,cleared,duration_sec`; hasil yang tidak cocok dengan tingkat labirin mana pun -> `invalid_score`; maks. 60 kiriman per pengguna per jam -> `too_many_requests`), `GET /game/leaderboard?limit=` | session | `rpc_submit_game_score`, `rpc_get_leaderboard` |
| `GET /notifications?after_id=&limit=`, `POST /notifications/read` (`ids`) | session | `rpc_get_notifications`, `rpc_mark_notifications_read` |
| `POST /chat` (`message` 1-500 karakter, `history` maks. 6 giliran terakhir dipakai: `{role: user|assistant, content <= 1000}`) | session | (baru) |
| `POST /feedback` (`suggestion,impression`), `GET /feedback` | session | `rpc_submit_feedback`, `rpc_get_my_feedback` |
| `POST /admin/giveaways` (tanpa `id` = buat, dengan `id` = ubah) | admin | `rpc_admin_upsert_giveaway` |
| `POST /admin/giveaways/:id/codes` (`count`; `geo_*` per kode ditolak `invalid_input` field `geo`), `GET` daftar | admin | `rpc_admin_generate_codes`, `rpc_admin_list_codes` |
| `GET /admin/giveaways` (`limit`, `offset`; semua status, terbaru dulu; `GET /giveaways` publik bawaannya `active` + `upcoming`, dengan `q` semua status) | admin | (baru) |
| `POST /admin/giveaways/:id/draw` | admin | `rpc_admin_run_draw` |
| `POST /internal/tick` | `X-Tick-Secret` | `fn_run_due_draws` |

Waktu pada `POST /admin/giveaways` (`start_at`, `end_at`, `draw_at`) wajib memakai zona (`Z` atau `+hh:mm`).
