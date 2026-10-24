# Code2Ticket: Database

Skema PostgreSQL (Supabase) dan migrasi SQL untuk backend Express (`../src`). Aplikasi Flutter memanggil
REST API backend, bukan tabel atau RPC; backend terhubung sebagai pemilik tabel. Detail API: [../README.md](../README.md).

## Isi folder

| File | Fungsi | Status |
|---|---|---|
| `00_supabase_shim.sql` | Tiruan role/schema Supabase untuk uji lokal. JANGAN dijalankan di Supabase | Hanya uji lokal |
| `01_schema.sql` | Tabel, constraint, index, hak akses | Dipakai |
| `04_storage.sql` | Bucket foto profil Supabase Storage | **Tidak dipakai lagi** (foto disimpan di tabel `user_photos`, lihat 07) |
| `06_backend.sql` | Migrasi ke arsitektur Flutter -> Express -> Postgres; membuang `02_functions.sql` dan `03_cron.sql` lama | Dipakai |
| `07_user_photos.sql` | Foto profil di database | Dipakai |
| `08_prize_value_idr.sql` | Nilai hadiah dalam rupiah (`prize_value_idr`) | Dipakai |
| `09_giveaway_participation.sql` | Info cara mendapat kode dan tautan penyelenggara | Dipakai |
| `10_redeem_geo_restricted.sql` | Pembatasan lokasi tukar kode di level giveaway | Dipakai |
| `11_organizer_contact.sql` | Dua baris kosong `app_config` untuk kontak penyelenggara | Dipakai |
| `12_chain_anchors.sql` | Tabel `chain_anchors`: catatan jangkar hash blok ke blockchain testnet | Dipakai |

Nomor 02, 03, dan 05 tidak ada di repo: `02_functions.sql` dan `03_cron.sql` digantikan kode Node.js
(scheduler di `../src/services/scheduler.js`), `05_bootstrap_admin.sql` digantikan `npm run create-admin`.

## Cara menjalankan

Jalankan berurutan di Supabase SQL Editor (atau `psql`): `01` -> `06` -> `07` -> `08` -> `09` -> `10` -> `11` -> `12`.
Lewati `00` dan `04`. `01_schema.sql` untuk database kosong; `06` sampai `12` aditif dan aman diulang.
Urutan deploy per migrasi (SQL dulu, baru backend, baru APK) ada di komentar kepala tiap file dan di
[../README.md](../README.md). Jangan memakai `drop schema public cascade`: itu menghapus hak default Supabase.

Akun admin pertama: `npm run create-admin` di `backend/`. Role `admin` sengaja tidak bisa dipilih dari aplikasi.

## Menjalankan uji

Butuh PostgreSQL uji dan Python 3 (lihat [../README.md](../README.md)). Tiap file tes membuat database baru
dari `00` + `01` + migrasi `06`-`12` (`../test/helpers.js`).

```bash
npm test
```

## Kontrak yang harus sama persis di Dart

Tiga hal ini dihitung di server **dan** di aplikasi. Perbedaan satu karakter membuat verifikasi gagal.
Implementasi acuan: `../src/lib/chain.js` dan `../test/reference/test_m1.py` (`client_hash`, `block_hash`, `pick_winners`, `verify`).

### 1. Hash password di aplikasi

```
salt          = string dari `POST /auth/salt` / dibuat saat register (32 karakter hex, dipakai SEBAGAI TEKS UTF-8, bukan di-decode)
password_hash = hex-huruf-kecil( PBKDF2-HMAC-SHA256(password UTF-8, salt UTF-8, 10.000 iterasi, 32 byte) )   -> 64 karakter
```

Saat register aplikasi membuat salt acak 16 byte → hex (32 karakter). Server menyimpan
`bcrypt(password_hash)`, jadi database yang bocor tidak memberi nilai yang bisa langsung dipakai login.
Dart: paket `pointycastle` (`PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))`) dan `cryptography`/`convert`.

Alur login: `POST /auth/salt` (identifier) → hitung `password_hash` → `POST /auth/login` (identifier, password_hash).

### 2. Hash block

Semua nilai ditulis sebagai teks, UUID huruf kecil, `ts_ms` bilangan bulat (epoch milidetik UTC),
dipisah `|`. `block_hash = hex-huruf-kecil(SHA-256(UTF-8 dari string))`.

```
COMMIT: C|{block_index}|{giveaway_id}|{seed_hash}|{winner_count}|{ts_ms}|{previous_hash}
RESULT: R|{block_index}|{giveaway_id}|{draw_id}|{seed}|{total_tickets}|{tickets_hash}|{winning_tickets}|{ts_ms}|{previous_hash}
```

- `previous_hash` block pertama = 64 karakter `0`.
- `winning_tickets` = nomor tiket pemenang berurutan dipisah koma (kosong `""` bila tak ada pemenang).

### 3. Pemilihan pemenang

`owner_key = hex-huruf-kecil(SHA-256("<user_id>:<giveaway_id>"))`, 12 karakter pertama (UUID huruf kecil). Satu pengguna punya satu `owner_key` per giveaway.

```
tickets      = daftar [nomor_tiket, owner_key] dari `GET /giveaways/:id/verification`, terurut naik menurut nomor
tickets_hash = hex(SHA-256( join(",", ["<nomor>:<owner_key>", ...]) ))       // "" -> hash dari string kosong
pool = tickets;  j = 0;  pemenang = []
selama |pemenang| < winner_count dan pool tidak kosong:
    h   = SHA-256( "<seed>:<giveaway_id>:<tickets_hash>:<j>" )                // bytes
    v   = 7 byte pertama h sebagai bilangan big-endian tak bertanda (56 bit)
    idx = v mod |pool|                                                        // 0-based
    pemenang += pool[idx].nomor
    hapus dari pool SEMUA tiket dengan owner_key yang sama dengan pool[idx]   // satu pengguna satu hadiah
    j += 1
```

`seed` berupa string hex 64 karakter, dipakai sebagai teks. 56 bit muat di `int` 64-bit Dart pada
Android/iOS. Jangan memakai Flutter Web untuk bagian ini (bilangan bulat 53-bit); atau pakai `BigInt`.

### 4. Pemeriksaan yang dilakukan layar Verifikasi

1. Setiap `block_hash` dihitung ulang dan `previous_hash` cocok dengan block sebelumnya.
2. `SHA-256(seed)` di result block = `seed_hash` di commit block giveaway yang sama.
3. `ts_ms` commit block ≤ `first_ticket_ms` (commit dibuat sebelum tiket pertama).
4. `tickets_hash` dan daftar pemenang yang dihitung ulang sama dengan result block.

Sebelum draw, `GET /giveaways/:id/verification` hanya mengembalikan commit block (`tickets` = `null`):
layar menampilkan "seed terkunci, dibuka saat draw".

## Batasan

- Tanpa Supabase Auth tidak ada JWT per pengguna; keamanan bertumpu pada sesi di backend dan pencabutan hak tabel dari `anon`.
- Seed tersimpan di database penyelenggara: tidak dapat diganti tanpa ketahuan (commit-reveal), tetapi pemegang akses penuh database dapat membacanya sebelum draw.
- Nilai game (skor/XP) dikirim oleh aplikasi sehingga dapat dipalsukan; server hanya membatasi rentang dan XP harian. XP bersifat kosmetik.
- `ts_ms` berasal dari jam server database.
