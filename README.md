# Code2Ticket

Aplikasi mobile Flutter untuk undian berhadiah (giveaway) digital: pengguna memasukkan kode voucher -> memperoleh tiket undian digital -> pengundian terjadwal/manual -> pemenang dapat diverifikasi secara transparan langsung di perangkat melalui *hash-chain* (prinsip *commit-reveal*).

## Arsitektur

- **Frontend (`app/`)**: Flutter (Android & Windows), State Management Provider/ChangeNotifier, SQLite lokal (`sqflite`) untuk cache & riwayat pesan, OpenStreetMap (`flutter_map`) untuk visualisasi peta & pencarian Terdekat (LBS).
- **Backend (`backend/`)**: Node.js Express (ESM), PostgreSQL (Supabase / local Postgres), Express Rate Limit, node-cron scheduler + endpoint tick, integrasi OpenAI Chat Completions untuk Asisten AI.
- **Kriptografi & Verifikasi**: PBKDF2-HMAC-SHA256 client-side password hashing, SHA-256 block chain commit-reveal untuk pengundian pemenang yang tahan manipulasi.

---

## Menjalankan & demo

### 1. Cara Menjalankan Aplikasi Mobile

Masuk ke direktori `app/` dan pasang dependensi Flutter:

```bash
cd app
flutter pub get
```

Jalankan aplikasi di emulator atau perangkat fisik (arahkan `API_BASE_URL` ke backend Render atau backend lokal):

```bash
# Menghubungkan ke backend server di Render
flutter run --dart-define=API_BASE_URL=https://code2ticket.onrender.com

# Atau menghubungkan ke server lokal (ganti IP sesuai host mesin / 10.0.2.2 untuk Android emulator)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

> **Catatan Windows:** Proyek dikonfigurasi dengan `kotlin.incremental=false` di `android/gradle.properties` demi kestabilan build Android di lingkungan drive multi-partisi.

---

### 2. Build APK Android

Untuk mengompilasi berkas APK installer Android (debug atau release):

```bash
cd app

# Build APK Release (untuk distribusi / pengujian performa rilis)
flutter build apk --release --dart-define=API_BASE_URL=https://code2ticket.onrender.com

# Build APK Debug (untuk pengujian cepat / inspeksi log)
flutter build apk --debug --dart-define=API_BASE_URL=https://code2ticket.onrender.com
```

Berkas keluaran APK akan berada di:
- Release: `app/build/app/outputs/flutter-apk/app-release.apk`
- Debug: `app/build/app/outputs/flutter-apk/app-debug.apk`

---

### 3. Alur Demo 5 Menit

Alur skenario pengujian komprehensif berdurasi 5 menit untuk mendemokan seluruh fitur utama:

1. **Menit 0:00 – 0:50: Autentikasi, Profil & Pengaturan**
   - Buka aplikasi.
   - Daftarkan akun baru di layar **Daftar** (atau login dengan akun yang sudah dibuat).
   - Masuk ke tab **Profil**:
     - Cek profil pengguna, level & badge XP.
     - Unggah foto profil (opsional).
     - Buka menu **Pengaturan**: ganti tema (Terang / Gelap), ganti zona waktu (WIB, WITA, WIT, UTC), ganti mata uang tampilan nilai hadiah (bawaan Rupiah; nilai dasar hadiah selalu rupiah, kurs Frankfurter) dan mata uang acuan di **Konverter**.
     - Aktifkan kunci biometrik (bila perangkat mendukung).

2. **Menit 0:50 – 1:50: Jelajah Giveaway, Peta OSM & Fitur Terdekat**
   - Masuk ke tab **Discover**:
     - Cari giveaway berdasarkan kata kunci pencarian.
     - Filter berdasarkan kategori (gaming, tech, food, fashion, travel).
     - Tekan ikon **Peta** di kanan atas untuk melihat penanda (marker) giveaway pada OpenStreetMap (OSM) interaktif.
     - Uji mode **Terdekat**: aktifkan chip *Terdekat* (pilih radius 5 km, 10 km, atau 25 km). Fitur akan meminta izin lokasi atau dapat menggunakan pencarian lokasi manual (Nominatim) untuk simulasi lokasi Surabaya atau Jakarta.

3. **Menit 1:50 – 2:40: Penukaran Kode & Verifikasi Lokasi**
   - Tekan tombol melayang (**FAB Input Code**) di bagian tengah bawah.
   - Masukkan kode demo dari `npm run demo-seed`:
     - **Uji verifikasi lokasi**: coba tukar kode giveaway Surabaya/Jakarta saat berada di luar radius area -> sistem menampilkan galat `out_of_area` ("Kamu berada di luar area giveaway ini...") dan tombol bantuan "Gunakan lokasiku".
     - **Tukar kode yang valid**: masukkan kode yang sesuai lokasi (atau kode tanpa batas lokasi dari giveaway Laptop Gaming) -> berhasil membuat tiket undian digital! Nomor tiket diterbitkan secara urut dan tercatat di hash-chain.

4. **Menit 2:40 – 3:30: Tiket Saya & Pengundian (Draw Otomatis / Manual)**
   - Buka tab **My Tickets**: lihat tiket yang baru saja diperoleh, berstatus *eligible* (menunggu undian).
   - **Pelaksanaan Draw**:
     - *Otomatis*: tunggu jadwal `draw_at` giveaway tiba (dieksekusi oleh scheduler backend atau panggilan `POST /internal/tick`).
     - *Manual (Admin)*: login menggunakan akun role Admin -> buka menu **Admin** di tab Profil -> pilih giveaway yang ingin diundi -> tekan **Draw Sekarang**.
   - Buka kembali tiket pada giveaway yang sudah diundi: nikmati animasi hasil undian (*shake to reveal* menggunakan sensor akselerometer perangkat). Tampil pengumuman pemenang transparan.

5. **Menit 3:30 – 4:10: Cek Keaslian (Verifikasi Hash-Chain & Commit-Reveal)**
   - Di layar detail giveaway yang telah di-draw atau riwayat tiket, pilih **Cek Keaslian**.
   - Perangkat melakukan verifikasi kriptografis lokal:
     - Memeriksa keabsahan block commit (seed hash yang di-commit sebelum tiket dibuat).
     - Memeriksa setiap block tiket terhubung secara berurutan (*tamper-evident*).
     - Memverifikasi pembukaan seed (*reveal*) dan menghitung ulang seed pemenang secara independen di Dart.
     - Indikator hijau menandakan bahwa undian 100% otentik dan bebas manipulasi admin/server.

6. **Menit 4:10 – 5:00: Asisten AI & Game Maze**
   - Masuk ke tab **Asisten**:
     - Ajukan pertanyaan seputar rekomendasi giveaway (mis. *"Giveaway apa yang cocok untuk pecinta kuliner di Surabaya?"* atau *"Ada giveaway teknologi apa saja yang aktif?"*).
     - Asisten menjawab secara kontekstual menggunakan OpenAI Chat Completions dan RAG berbasis giveaway aktif, lengkap dengan kartu tautan langsung.
   - Masuk ke menu **Game** (Home > Menu fitur > Game), lalu pilih **Buru Kode**:
     - Mainkan labirin interaktif menggunakan sensor kemiringan ponsel (gyroscope/accelerometer) atau tombol panah di layar.
     - Antar chip kode ke Mesin Undian sebelum waktu habis sambil mengumpulkan segmen kode.
     - Kirim skor ke server dan lihat posisimu di **Papan Peringkat**, dibuka dari dalam fitur Game.

---

### 4. Akun Demo (Cara Pembuatan)

Repositori ini bersifat publik dan **TIDAK menyimpan kata sandi** akun apa pun di dalam berkas atau riwayat commit git. Penguji dapat menyiapkan akun demo dengan cara berikut:

1. **Akun Pengguna Biasa (User)**
   - Dibuat secara mandiri langsung melalui aplikasi mobile pada layar **Daftar** (Register).
   - Penguji bebas menentukan username (misal `user_demo1`, `peserta_surabaya`), email, nama lengkap, dan password yang diinginkan.
   - Password akan di-hash menggunakan PBKDF2-HMAC-SHA256 di sisi klien sebelum dikirim ke backend.

2. **Akun Administrator (Admin)**
   - Dibuat melalui terminal di direktori `backend/` menggunakan script `create-admin.js`.
   - Password dibaca dari variabel lingkungan terminal (tidak disimpan ke berkas/history):

     **Linux / macOS / Git Bash:**
     ```bash
     cd backend
     ADMIN_PASSWORD='PasswordKuatAdmin123!' npm run create-admin -- admin_demo admin@example.com "Admin Demo"
     ```

     **Windows PowerShell:**
     ```powershell
     cd backend
     $env:API_BASE_URL = "https://code2ticket.onrender.com"
     $env:ADMIN_USERNAME = "admin_demo"
     $env:ADMIN_PASSWORD = Read-Host "Masukkan Password Admin"
     npm run create-admin -- admin_demo admin@example.com "Admin Demo"
     Remove-Item Env:ADMIN_PASSWORD
     ```

3. **Menjalankan Demo Seed (Data Giveaway & Kode Idempotent)**
   - Setelah akun admin dibuat, jalankan script demo seed untuk menyiapkan giveaway dan kode voucher:
     ```bash
     cd backend
     API_BASE_URL=https://code2ticket.onrender.com ADMIN_USERNAME=admin_demo ADMIN_PASSWORD='PasswordKuatAdmin123!' npm run demo-seed
     ```
   - Script akan menampilkan daftar kode promo unik yang siap disalin dan ditukarkan di aplikasi mobile.

---

### 5. Daftar Environment Variable Render

Berikut adalah daftar nama variabel lingkungan yang digunakan backend saat di-deploy di layanan Render (hanya nama variabel, tanpa mencantumkan nilai rahasia):

| Nama Variabel Lingkungan | Deskripsi |
|---|---|
| `NODE_ENV` | Mode lingkungan Node.js (`production` / `development`) |
| `PORT` | Port server aplikasi Express (diatur otomatis oleh Render) |
| `DATABASE_URL` | URL koneksi langsung ke basis data PostgreSQL (Supabase / Postgres) |
| `DATABASE_SSL` | Mode koneksi SSL database (`disable` / `require` / `verify-full`) |
| `DB_POOL_MAX` | Batas maksimum koneksi pool database pg |
| `CORS_ORIGINS` | Daftar origin domain web yang diizinkan (opsional untuk klien mobile) |
| `TICK_SECRET` | Rahasia otentikasi header `X-Tick-Secret` untuk memicu endpoint `POST /internal/tick` |
| `SCHEDULER_ENABLED` | Menyalakan atau mematikan scheduler background `node-cron` (`true` / `false`) |
| `RATE_LIMIT_MAX` | Batas maksimum permintaan API umum per IP per menit |
| `AUTH_RATE_LIMIT_MAX` | Batas maksimum permintaan endpoint `/auth/*` per IP per menit |
| `UPLOAD_RATE_LIMIT_MAX` | Batas maksimum permintaan unggah foto `/me/photo` per IP per menit |
| `OPENAI_API_KEY` | Kunci API OpenAI untuk fitur chat Asisten AI |
| `OPENAI_MODEL` | Identifikasi nama model OpenAI (wajib diisi, misal model GPT Chat Completions) |
| `AI_DAILY_LIMIT_PER_USER` | Kuota harian pesan chat Asisten AI per pengguna (default 30) |
| `AI_RATE_PER_MINUTE` | Batas laju percakapan Asisten AI per pengguna per menit (default 8) |
| `OPENAI_TIMEOUT_MS` | Batas waktu timeout pemanggilan API OpenAI dalam milidetik |
| `TRUST_PROXY` | Jumlah lapis reverse proxy di depan server (wajib `1` di Render agar rate limit mendeteksi IP asli klien) |
| `ANCHOR_ENABLED` | `true` menyalakan jangkar hash blok ke blockchain testnet; selain itu mati (lihat `backend/README.md` "Jangkar blockchain") |
| `ANCHOR_RPC_URL` | URL JSON-RPC pengirim transaksi jangkar (boleh memuat API key; rahasia) |
| `ANCHOR_CHAIN_ID` | Chain id tujuan (bawaan `80002`, Polygon Amoy) |
| `ANCHOR_PRIVATE_KEY` | Kunci privat dompet testnet khusus jangkar (rahasia; buat dengan perintah di `backend/README.md`, jangan disimpan di repo) |
| `ANCHOR_EXPLORER_TX_URL` | Templat tautan explorer transaksi, mis. `https://amoy.polygonscan.com/tx/{tx}` |
| `ANCHOR_PUBLIC_RPC_URL` | RPC https tanpa key yang boleh dilihat aplikasi (bawaan RPC publik Amoy) |
