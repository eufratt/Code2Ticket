# Code2Ticket: panduan agent

## Ringkasan
Aplikasi mobile Flutter (tugas akhir Pemrograman Aplikasi Mobile): pengguna memasukkan kode -> tiket undian digital -> draw otomatis terjadwal ->
pemenang dapat diverifikasi lewat hash-chain (commit-reveal). Bahasa antarmuka dan komentar: Indonesia.

## Arsitektur
Flutter (app\) -> HTTPS -> Express (backend\, di Render: https://code2ticket.onrender.com) -> Postgres (Supabase, hanya sebagai database).
Aplikasi tidak memakai Supabase Auth, anon key, maupun akses tabel langsung. SQLite lokal di app untuk cache, riwayat pencarian, dan pengaturan.
Login/session dibuat sendiri (bukan Firebase/Supabase Auth). Scheduler draw: node-cron + endpoint /internal/tick yang dipanggil tiap menit (Render free bisa tertidur).

## Struktur
- app\      Flutter. lib\core (api, crypto, db, security, session), lib\features (auth, giveaways, tickets, profile, shell), test\
- backend\  Express (JavaScript ESM). src\ (rute, services, lib), db\ (01_schema.sql, 06_backend.sql, shim uji), test\ (vitest), scripts\demo-seed.js
- Dokumen (PRD, ERD, Context) ada DI LUAR repo: ..\docs\ (hanya dibaca; jangan disalin ke repo). Istilah RPC di dokumen itu sudah usang;
  bila bertentangan dengan kode, yang berlaku adalah backend\src dan backend\README.md. Laporkan pertentangannya.

## Perintah
- Flutter (di app\): flutter pub get ; flutter analyze --no-pub ; flutter test ;
  flutter run --dart-define=API_BASE_URL=https://code2ticket.onrender.com
- Backend (di backend\): npm ci ; npm test (butuh Postgres uji dan Python 3, lihat backend\README.md) ; npm run demo-seed (env ADMIN_USERNAME/ADMIN_PASSWORD/API_BASE_URL)
- Android: android\gradle.properties berisi kotlin.incremental=false (proyek di drive D:, pub cache di C:); jangan dihapus.

## Kontrak yang tidak boleh diubah diam-diam
- Password: klien menghitung PBKDF2-HMAC-SHA256 (10.000 iterasi, 32 byte, salt 32 hex dipakai sebagai TEKS UTF-8, hasil hex huruf kecil);
  server menyimpan bcrypt(hash klien). Lihat app\lib\core\crypto\password_hasher.dart dan tesnya.
- Hash block draw_chain dan algoritma pemilihan pemenang harus identik di backend dan di Dart: backend\src\lib\chain.js, backend\test\reference\test_m1.py.
  draw_chain append-only (trigger database). Seed dibuat saat giveaway dibuat; hash-nya di-commit di block pertama; seed dibuka saat draw.
- Respons API: gagal bisnis HTTP 200 {"ok":false,"error":"<kode>"}; sesi tidak valid 401 invalid_session; bukan admin 403 forbidden.
- Token session dikirim lewat header Authorization: Bearer; server hanya menyimpan SHA-256-nya; di app disimpan di flutter_secure_storage.

## Aturan kerja
- Repo PUBLIC. Jangan pernah meng-commit rahasia: .env, DATABASE_URL, TICK_SECRET, password, token, kunci API. URL hanya lewat --dart-define / env.
- Jangan git push dan jangan --force kecuali diminta. Commit per fitur, pesan Indonesia yang jelas, tanpa trailer co-author.
- Sebelum menyatakan selesai: flutter analyze --no-pub dan flutter test bersih; bila backend disentuh, tes backend juga tidak boleh rusak.
- Permintaan POST yang mengubah data (register, redeem, dll.) tidak boleh di-retry otomatis. Server Render free bisa lambat saat bangun: tampilkan "Server sedang bangun" (isWakingUp).
- State management: Provider/ChangeNotifier. Jangan menambah state management baru. Parsing JSON lewat kelas model, bukan Map mentah di UI.
- Jangan simpan token/password di SQLite. Jangan simpan lokasi pengguna di server maupun lokal.
- Jangan ubah password_hasher.dart, tes hash, kontrak hash/draw, atau skema database tanpa persetujuan eksplisit; bila menemukan bug di backend, laporkan.
- Bila ragu pada keputusan yang tidak bisa dibalik atau PRD dan kode bertentangan, berhenti dan tanya.

## Status milestone
Selesai: M1 database; M2 auth + biometric + SQLite dasar; M3 navigasi 5 tab (FAB Input Code melayang), Home, Detail Giveaway, Input Code, My Tickets;
perbaikan navbar; M4 Discover (cari + riwayat, filter, peta OSM, Terdekat/LBS, lokasi manual Nominatim, cache offline, GET /giveaways/:id).
Sisa: M5 konversi mata uang (IDR/USD/EUR/JPY) dan zona waktu (WIB/WITA/WIT/London), notifikasi, profil, Saran & Kesan, Admin;
M6 draw end-to-end, verifikasi hash-chain di app, shake to reveal; M7 AI Assistant (lewat backend, kunci LLM hanya di server), rekomendasi, mini game, leaderboard; M8 pengujian dan data demo; M9 laporan.

## Peta kode (graphify)
Bila graphify-out\GRAPH_REPORT.md ada, baca dulu sebelum mencari file satu per satu. Perbarui dengan "graphify update ." setelah perubahan besar
(hook git sudah memperbarui otomatis setelah commit). graphify-out\ tidak di-commit.
