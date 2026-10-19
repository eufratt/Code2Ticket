# Code2Ticket: panduan agent

## Ringkasan
Aplikasi mobile Flutter (tugas akhir Pemrograman Aplikasi Mobile): pengguna memasukkan kode -> tiket undian digital -> draw otomatis terjadwal ->
pemenang dapat diverifikasi lewat hash-chain (commit-reveal). Bahasa antarmuka dan komentar: Indonesia.

## Arsitektur
Flutter (app\) -> HTTPS -> Express (backend\, di Render: https://code2ticket.onrender.com) -> Postgres (Supabase, hanya sebagai database).
Aplikasi tidak memakai Supabase Auth, anon key, maupun akses tabel langsung. SQLite lokal di app untuk cache, riwayat pencarian, pengaturan, dan riwayat chat Asisten (tabel chat_messages, DB lokal v2).
Login/session dibuat sendiri (bukan Firebase/Supabase Auth). Scheduler draw: node-cron + endpoint /internal/tick yang dipanggil tiap menit (Render free bisa tertidur).

## Struktur
- app\      Flutter. lib\core (api, crypto, db, security, session), lib\features (auth, giveaways, tickets, profile, assistant, shell), test\
- backend\  Express (JavaScript ESM). src\ (rute, services, lib), db\ (01_schema.sql, 06_backend.sql, shim uji), test\ (vitest), scripts\demo-seed.js
- Dokumen (PRD, ERD, Context) ada DI LUAR repo: ..\docs\ (hanya dibaca; jangan disalin ke repo). Istilah RPC di dokumen itu sudah usang;
  bila bertentangan dengan kode, yang berlaku adalah backend\src dan backend\README.md. Laporkan pertentangannya.

## Perintah
- Flutter (di app\): flutter pub get ; flutter analyze --no-pub ; flutter test ;
  flutter run --dart-define=API_BASE_URL=https://code2ticket.onrender.com
- Backend (di backend\): npm ci ; npm test (butuh Postgres uji dan Python 3, lihat backend\README.md) ; npm run demo-seed (env ADMIN_USERNAME/ADMIN_PASSWORD/API_BASE_URL)
- Kontrol Maze: logika kemiringan murni di app\libeatures\game	ilt_filter.dart (parameter tiltTau/zona mati/gain/batas didokumentasikan di sana, tesnya app	est\game	ilt_filter_test.dart); adaptor sensor_plus di tilt.dart. Jangan menaruh logika filter di layar.
- Android: android\gradle.properties berisi kotlin.incremental=false (proyek di drive D:, pub cache di C:); jangan dihapus.

## Navigasi
Bottom navigation 4 item sama lebar: Home, Profil (ikon = foto profil), Saran & Kesan, Logout; tanpa FAB (kerangka: app\lib\features\shell\app_shell.dart, rute: app\lib\app_router.dart).
Home, Profil, dan Saran & Kesan adalah 3 cabang StatefulShellRoute; Logout hanya aksi (dialog konfirmasi + alur logout yang sudah ada), tidak pernah menjadi tab terpilih.
Home adalah pusat fitur (tombol Input Code + grid Menu fitur). Discover, My Tickets, Asisten, Input Code, Game, Papan Peringkat, Konverter, dan Peta adalah rute tingkat atas
yang dibuka dengan context.push dari Home (layar penuh, tombol kembali, tanpa bottom nav). Jangan memakai context.go untuk membuka layar fitur (tumpukan Home hilang); gunakan push / pushReplacement.
Padding bawah daftar di dalam shell = Spacing.listBottom (tinggi bar + 16).

## Kontrak yang tidak boleh diubah diam-diam
- Password: klien menghitung PBKDF2-HMAC-SHA256 (10.000 iterasi, 32 byte, salt 32 hex dipakai sebagai TEKS UTF-8, hasil hex huruf kecil);
  server menyimpan bcrypt(hash klien). Lihat app\lib\core\crypto\password_hasher.dart dan tesnya.
- Hash block draw_chain dan algoritma pemilihan pemenang harus identik di backend dan di Dart: backend\src\lib\chain.js, backend\test\reference\test_m1.py.
  draw_chain append-only (trigger database). Seed dibuat saat giveaway dibuat; hash-nya di-commit di block pertama; seed dibuka saat draw.
- Respons API: gagal bisnis HTTP 200 {"ok":false,"error":"<kode>"}; sesi tidak valid 401 invalid_session; bukan admin 403 forbidden.
- Token session dikirim lewat header Authorization: Bearer; server hanya menyimpan SHA-256-nya; di app disimpan di flutter_secure_storage.

## Aturan kerja
- Repo PUBLIC. Jangan pernah meng-commit rahasia: .env, DATABASE_URL, TICK_SECRET, password, token, kunci API. URL hanya lewat --dart-define / env.
- Jangan git push dan jangan --force kecuali diminta. Commit per fitur dalam bahasa Inggris menggunakan format Conventional Commits (mis. "feat: add admin giveaway form", "fix: handle empty notifications"), tanpa trailer co-author.
- Sebelum menyatakan selesai: flutter analyze --no-pub dan flutter test bersih; bila backend disentuh, tes backend juga tidak boleh rusak.
- Permintaan POST yang mengubah data (register, redeem, dll.) dan POST /chat (biaya LLM) tidak boleh di-retry otomatis. Server Render free bisa lambat saat bangun: tampilkan "Server sedang bangun" (isWakingUp).
- State management: Provider/ChangeNotifier. Jangan menambah state management baru. Parsing JSON lewat kelas model, bukan Map mentah di UI.
- Kunci OpenAI (OPENAI_API_KEY) hanya ada di env server (Render/.env lokal): jangan di repo, app, log, atau respons. Env AI lain: OPENAI_MODEL (wajib), AI_DAILY_LIMIT_PER_USER; lihat backend\README.md.
- Jangan simpan token/password di SQLite. Jangan simpan lokasi pengguna di server maupun lokal.
- Jangan ubah password_hasher.dart, tes hash, kontrak hash/draw, atau skema database tanpa persetujuan eksplisit; bila menemukan bug di backend, laporkan.
- Bila ragu pada keputusan yang tidak bisa dibalik atau PRD dan kode bertentangan, berhenti dan tanya.

## UI
Semua tampilan mengikuti DESIGN.md (token, komponen bersama di app\lib\core\widgets, tema di app\lib\core\theme). Jangan membuat gaya baru per layar; perbarui DESIGN.md bila pola berubah.
Sebelum commit layar UI, centang daftar periksa di bagian 9 DESIGN.md.

## Status milestone
Selesai: M1 database; M2 auth + biometric + SQLite dasar; M3 navigasi (sekarang 4 item: lihat "Navigasi"), Home, Detail Giveaway, Input Code, My Tickets;
perbaikan navbar; M4 Discover (cari + riwayat, filter, peta OSM, Terdekat/LBS, lokasi manual Nominatim, cache offline, GET /giveaways/:id);
M5a kurs Frankfurter (langsung dari app) + zona waktu 4 zona + hitung mundur, Konverter, Pengaturan, Profil + foto (PUT /me/photo, butuh backend\db\07_user_photos.sql), Saran & Kesan.
Desain DESIGN.md diterapkan ke semua layar yang ada (tema terang/gelap, komponen bersama, tes tata letak).
M5b notifikasi (lonceng + lencana di Home, layar Notifikasi) dan Admin (menu hanya untuk role admin: Buat Giveaway, Generate Code, Daftar Kode, Draw manual).
M6 hasil draw, verifikasi hash-chain di perangkat (app\lib\core\verify, vektor dari test_m1.py di app\test\fixtures), shake to reveal (sensors_plus).
M7a Game Maze (kemiringan = filter komplementer gyroscope + accelerometer, fallback accelerometer saja; kalibrasi saat Mulai + tombol "Kalibrasi ulang"; D-pad; skor ke /game/scores), papan peringkat, rekomendasi "Untuk kamu" (/me/affinity) dan pencatatan aktivitas (/activity).
M7b Asisten AI: POST /chat (OpenAI Chat Completions lewat fetch, RAG sederhana dari giveaway aktif, batas pemakaian di memori), layar Asisten (gelembung chat, saran cepat, kartu giveaway, riwayat SQLite per pengguna, hapus percakapan, kirim ulang manual).
M8a utang teknis backend: status giveaway dihitung saat dibaca, seed_mismatch tidak diulang scheduler, hanya tebakan kode yang dihitung ke batas redeem, pembersihan login_attempts tiap jam (juga dari /internal/tick), salt palsu = format salt asli (register hanya menerima 32 hex). Detail dan saran rate limit demo: backend\README.md.
Sisa:
M8 pengujian dan data demo; M9 laporan.

## Peta kode (graphify)
Bila graphify-out\GRAPH_REPORT.md ada, baca dulu sebelum mencari file satu per satu. Perbarui dengan "graphify update ." setelah perubahan besar
(hook git sudah memperbarui otomatis setelah commit). graphify-out\ tidak di-commit.
