# Code2Ticket

Aplikasi mobile Flutter untuk undian berhadiah (giveaway) digital: pengguna memasukkan kode -> memperoleh tiket undian -> draw terjadwal atau manual -> pemenang dapat diverifikasi di perangkat lewat *hash-chain* (commit-reveal), dengan hash blok yang dijangkarkan ke blockchain testnet publik.

## Arsitektur

```
Flutter (app/)  --HTTPS-->  Express (backend/)  -->  PostgreSQL
```

- **`app/`**: Flutter (Android dan Windows), Provider/ChangeNotifier, SQLite lokal (`sqflite`) untuk cache, riwayat pencarian, pengaturan, dan riwayat chat; peta OpenStreetMap (`flutter_map`).
- **`backend/`**: Node.js 20+ (Express 5, ESM). Memakai Postgres lewat `DATABASE_URL` langsung (Supabase hanya sebagai penyedia database; tanpa Supabase Auth/anon key). Scheduler `node-cron` + `POST /internal/tick`, asisten AI (OpenAI Chat Completions), jangkar hash blok ke testnet EVM (`viem`; bawaan Ethereum Sepolia).
- **Kriptografi**: PBKDF2-HMAC-SHA256 di klien (server menyimpan bcrypt dari hash klien); hash-chain SHA-256 identik di backend dan Dart.

Struktur dan aturan kerja: [AGENTS.md](AGENTS.md). Panduan UI: [DESIGN.md](DESIGN.md). Detail backend dan API: [backend/README.md](backend/README.md).

## Cara menjalankan

- **Backend produksi**: https://code2ticket.onrender.com. Layanan gratis Render bisa tertidur; buka URL itu dulu dan tunggu sekitar satu menit sebelum memakai aplikasi.
- **Aplikasi**: `cd app`, `flutter pub get`, `flutter run`. Bawaan memakai backend produksi; backend lokal lewat `--dart-define=API_BASE_URL=...` (lihat di bawah).
- **Backend lokal** (opsional): `cd backend`, `npm install`, salin `.env.example` ke `.env` dan isi, lalu `npm start`. Butuh PostgreSQL dan migrasi SQL (lihat "Menjalankan backend").
- Tidak ada akun atau kata sandi di repositori; daftar lewat layar **Daftar** di aplikasi.

## Prasyarat

- Flutter SDK dengan Dart `^3.12.2` dan toolchain Android (untuk APK).
- Node.js >= 20 dan npm.
- PostgreSQL dengan ekstensi `pgcrypto` dan `pg_trgm` (atau proyek Supabase).
- Python 3 (hanya untuk tes backend; tes kontrak memuat `backend/test/reference/test_m1.py`).

## Menjalankan backend

```bash
cd backend
npm ci
cp .env.example .env     # isi DATABASE_URL dan TICK_SECRET (minimal 16 karakter), dst.
```

Jalankan migrasi berurutan ke database (`psql "$DATABASE_URL" -f db/<berkas>`; di Supabase tempel di SQL Editor). Postgres non-Supabase: jalankan `db/00_supabase_shim.sql` lebih dulu.

| Urutan | Berkas | Isi |
|---|---|---|
| 1 | `01_schema.sql` | Skema dasar |
| 2 | `06_backend.sql` | Tabel dan kolom untuk backend Node |
| 3 | `07_user_photos.sql` | Foto profil |
| 4 | `08_prize_value_idr.sql` | Nilai hadiah dalam rupiah |
| 5 | `09_giveaway_participation.sql` | Cara mendapatkan kode dan tautan penyelenggara |
| 6 | `10_redeem_geo_restricted.sql` | Batas lokasi tukar kode per giveaway |
| 7 | `11_organizer_contact.sql` | Baris kontak admin untuk penyelenggara (kosong) |
| 8 | `12_chain_anchors.sql` | Jangkar blockchain |

`04_storage.sql` (bucket Supabase untuk foto profil lama) tidak dipakai lagi. Lalu buat admin dan jalankan server:

```bash
ADMIN_PASSWORD='...' npm run create-admin -- username email@contoh.com "Nama Lengkap"
npm start
```

## Menjalankan aplikasi

```bash
cd app
flutter pub get
flutter run --dart-define=API_BASE_URL=https://code2ticket.onrender.com
# backend lokal dari emulator Android:
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

APK (hasil di `app/build/app/outputs/flutter-apk/`):

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://code2ticket.onrender.com
```

`android/gradle.properties` berisi `kotlin.incremental=false` (proyek dan pub cache di drive berbeda); jangan dihapus.

## Variabel environment backend

Hanya nama; nilai diisi di `backend/.env` lokal atau env Render, tidak pernah di repo. Templat: [backend/.env.example](backend/.env.example).

| Kelompok | Variabel |
|---|---|
| Server | `NODE_ENV`, `PORT`, `TRUST_PROXY` (wajib `1` di Render), `CORS_ORIGINS` |
| Database | `DATABASE_URL` (rahasia), `DATABASE_SSL`, `DB_POOL_MAX` |
| Scheduler | `SCHEDULER_ENABLED`, `TICK_SECRET` (rahasia; header `X-Tick-Secret` untuk `POST /internal/tick`) |
| Rate limit | `RATE_LIMIT_MAX`, `AUTH_RATE_LIMIT_MAX`, `UPLOAD_RATE_LIMIT_MAX` |
| Asisten AI | `OPENAI_API_KEY` (rahasia), `OPENAI_MODEL`, `AI_DAILY_LIMIT_PER_USER`, `AI_DAILY_LIMIT_GLOBAL`, `AI_RATE_PER_MINUTE`, `OPENAI_TIMEOUT_MS` |
| Jangkar blockchain | `ANCHOR_ENABLED`, `ANCHOR_RPC_URL` (rahasia), `ANCHOR_CHAIN_ID`, `ANCHOR_PRIVATE_KEY` (rahasia), `ANCHOR_EXPLORER_TX_URL`, `ANCHOR_PUBLIC_RPC_URL` |

Fitur AI dan jangkar mati dengan aman bila variabelnya kosong atau tidak valid.

## Urutan deploy

1. Jalankan migrasi SQL yang baru di database (Supabase SQL Editor).
2. Set/ubah environment di Render.
3. `git push` (Render membangun ulang backend).
4. Bangun APK baru.

Urutan ini menjaga APK lama dan backend baru tetap berjalan; detail kompatibilitas per migrasi ada di [backend/README.md](backend/README.md).

## Tes

```bash
# Flutter (1127 tes)
cd app && flutter analyze && flutter test

# Backend (374 tes, 17 file): butuh Postgres uji; tiap file membuat database sendiri
cd backend && TEST_PG_URL=postgres://postgres@127.0.0.1:5432 npm test    # bawaan 127.0.0.1:54329
```

## Akun dan data demo

Repositori publik dan **tidak menyimpan kata sandi**. Pengguna biasa mendaftar lewat layar **Daftar**. Admin dibuat dengan `npm run create-admin` (sandi dari variabel `ADMIN_PASSWORD`, tidak ditulis ke berkas). Setelah itu data demo dibuat idempotent:

```bash
cd backend
API_BASE_URL=https://code2ticket.onrender.com ADMIN_USERNAME=<admin> ADMIN_PASSWORD=<sandi> npm run demo-seed
```

Skrip mencetak kode voucher ke terminal (hanya tampil sekali). Server gratis Render bisa butuh sekitar 1 menit untuk bangun.

## Alur demo singkat

1. Daftar/masuk, atur tema, zona waktu (WIB, WITA, WIT, London), mata uang tampilan, dan kunci biometrik di **Profil**.
2. Jelajahi giveaway di **Discover** (cari, filter, peta, mode Terdekat).
3. Tukar kode lewat tombol **Input Code** di Home; giveaway dengan batas lokasi memeriksa jarak ke lokasi giveaway.
4. Lihat tiket di **My Tickets**. Draw berjalan otomatis (scheduler) atau manual oleh admin; hasilnya dibuka dengan *shake to reveal*.
5. **Cek Keaslian**: perangkat menghitung ulang hash-chain, pemenang, dan memeriksa jangkar blockchain.
6. **Asisten** AI untuk rekomendasi giveaway dan **Game** (Buru Kode, Rakit Rantai) dengan papan peringkat.
