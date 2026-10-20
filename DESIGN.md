# Code2Ticket: Panduan UI (DESIGN.md)

Acuan tunggal tampilan. Semua layar memakai token dan komponen di sini. Jangan membuat gaya baru per layar.
Kode: `app/lib/core/theme/` (tema, token) dan `app/lib/core/widgets/` (komponen bersama).
Bila dokumen ini dan kode berbeda, perbarui salah satunya di commit yang sama.

## 1. Prinsip
1. **Terpercaya.** Undian harus terasa adil dan transparan: status jelas, waktu jelas, bukti (hash/verifikasi) mudah dicapai.
2. **Satu aksi utama per layar.** Tombol utama selalu terlihat dan hanya satu.
3. **Tiket adalah objek utama.** Tiket tampil sebagai kartu tiket (lekukan sobekan), bukan baris tabel.
4. **Selalu ada keadaan.** Setiap daftar punya loading (skeleton), kosong, error (dengan coba lagi), dan offline.
5. **Ringan dan konsisten.** Jarak, radius, dan font dari token; tidak ada angka ajaib di widget.

## 2. Acuan pola (pola umum, bukan salinan aplikasi)
| Bagian | Pola yang dirujuk | Penerapan |
|---|---|---|
| Tiket | E-ticket Tiket.com / Traveloka | Kartu dengan lekukan setengah lingkaran di sisi, garis putus-putus, nomor tiket besar, chip status |
| Home | Home Gojek / GoPay | Sapaan, ringkasan tiket, kolom cari, tombol utama, grid menu fitur, chip kategori, carousel horizontal, daftar |
| Detail | Halaman produk marketplace | Banner besar, nilai hadiah menonjol, hitung mundur, tombol aksi menempel di bawah |
| Verifikasi draw | Pelacakan paket Shopee | Timeline vertikal langkah demi langkah |
| Profil | Duolingo | Lingkaran level + bar XP, grid lencana |
| Chat AI | Bubble chat WhatsApp | Gelembung kiri (asisten) / kanan (pengguna), input di bawah |

## 3. Token

### 3.1 Warna (terang)
| Token | Nilai | Pemakaian |
|---|---|---|
| primary | `#4F46E5` | Tombol utama, tab aktif, tautan. Teks putih di atasnya (kontras 6,3) |
| primaryContainer | `#EEF2FF` | Latar chip/aksen lembut. Teks `#3730A3` (8,9) |
| accent (amber) | `#F59E0B` | **Hanya isi/ikon besar** (hadiah, lencana). Teks di atasnya `#1F2937` (6,8). JANGAN teks amber di atas putih (2,2) |
| accentText | `#B45309` | Teks/ikon amber kecil di atas putih (5,0) |
| success | `#16A34A` | **Hanya isi/ikon besar**. Teks hijau memakai `#15803D` (5,0). `#16A34A` sebagai teks gagal kontras (3,3) |
| error | `#DC2626` | Teks/ikon error (4,8). Latar error `#FEE2E2` dengan teks `#991B1B` |
| background | `#F8FAFC` | Latar layar |
| surface | `#FFFFFF` | Kartu |
| surfaceVariant | `#F1F5F9` | Kolom input, skeleton. Teks sekunder `#475569` (6,9) |
| onBackground | `#0F172A` | Teks utama (17:1) |
| onSurfaceMuted | `#475569` | Teks sekunder (7,6). `#64748B` (4,8) hanya untuk keterangan kecil |
| outline | `#E2E8F0` | Garis pembatas, garis putus tiket |

Latar status (chip): sukses `#DCFCE7` + teks `#166534`; peringatan `#FEF3C7` + teks `#92400E`; error `#FEE2E2` + teks `#991B1B`; info `#EEF2FF` + teks `#3730A3`; netral `#F1F5F9` + teks `#475569`. Semua di atas 6:1.

### 3.2 Warna (gelap)
background `#0F172A`, surface `#1E293B`, surfaceVariant `#334155`, onBackground `#E2E8F0` (14,5), onSurfaceMuted `#94A3B8` (5,7 di surface),
primary `#818CF8` (teks gelap `#0F172A` di atasnya, 6,0), accent `#FBBF24` (8,8), success `#4ADE80` (8,4), error `#F87171` (5,3).
Tema gelap harus punya padanan untuk setiap token terang; tidak ada warna yang hanya didefinisikan di satu tema.
Tambahan: `mutedOnVariant` = teks sekunder di atas surfaceVariant (kolom input): terang `#475569` (6,9), gelap `#CBD5E1` (7,5), karena `#94A3B8` di atas `#334155` hanya 4,0.
Latar chip status gelap: sukses `#14532D`/`#BBF7D0`, peringatan `#78350F`/`#FDE68A`, error `#7F1D1D`/`#FECACA`, info `#312E81`/`#C7D2FE`, netral `#334155`/`#CBD5E1` (semua di atas 7:1). Kontras semua pasangan token diperiksa otomatis di `test/theme/theme_test.dart`.

### 3.3 Warna kategori (banner tanpa gambar)
Gradien dua warna per kategori + ikon: gaming `#4F46E5→#7C3AED` (ikon gamepad), travel `#0EA5E9→#22D3EE` (pesawat), elektronik `#334155→#64748B` (laptop/chip),
fashion `#DB2777→#F472B6`, makanan `#EA580C→#FB923C`, lainnya `#4F46E5→#818CF8`. Teks putih di atas gradien harus kontras >= 4,5 (pakai lapisan gelap 20% bila perlu).
Kategori yang tidak dikenal memakai "lainnya". Warna per kategori konsisten di seluruh aplikasi.
Kode kategori backend dipetakan: `tech`=elektronik, `food`=makanan, `gaming`/`travel`/`fashion` sama, `lifestyle` dan `other`=lainnya. Lapisan gelap 20% selalu dipasang di atas gradien, dan teks tidak pernah ditaruh langsung di atas banner (hanya ikon putih dan chip bersolid).

### 3.4 Tipografi
Font: Plus Jakarta Sans (`google_fonts`; pastikan fallback bila offline tidak merusak tata letak). Angka tabular untuk nomor tiket, kurs, hitung mundur.
| Gaya | Ukuran/berat | Pemakaian |
|---|---|---|
| display | 28/700 | Angka besar (nomor tiket, hitung mundur) |
| title | 20/700 | Judul layar, judul kartu detail |
| subtitle | 16/600 | Judul kartu, header bagian |
| body | 14/400 (tinggi 1,45) | Isi |
| label | 12/600 | Chip, label tab, tombol kecil |
| caption | 12/400 | Keterangan, waktu pembaruan |
Dukung skala font sistem sampai 1,3x tanpa overflow (pakai `Flexible`/`Wrap`, bukan lebar tetap).

### 3.5 Jarak, bentuk, bayangan, gerak
- Jarak (dp): 4, 8, 12, 16, 24, 32 (kelipatan 4/8). Padding layar 16. Jarak antar kartu 12. Jarak antar bagian 24.
- Radius: 8 (chip kecil, input), 12 (tombol), 16 (kartu), 24 (sheet atas), penuh (avatar, ikon bulat).
- Bayangan: kartu `0 2 8 rgba(15,23,42,0.06)`; kartu terangkat `0 6 16 rgba(15,23,42,0.10)`; logo merek `0 8 20 rgba(79,70,229,0.35)`. Mode gelap: kurangi bayangan, andalkan beda warna surface.
- Gerak: 150-250 ms, kurva ease-out; transisi layar standar; animasi hanya untuk memberi makna (sukses tiket, hitung mundur, skeleton). Hormati "kurangi animasi" sistem.
- Tap target >= 48x48 dp.

## 4. Komponen bersama (`core/widgets/`)
- **TicketCard**: kartu tiket dua bagian. Kiri/atas: nama giveaway, kategori, nilai hadiah. Kanan/bawah (setelah garis putus): nomor tiket (display, tabular), status.
  Lekukan setengah lingkaran (radius 10) di titik garis putus pada kedua sisi (`CustomPainter`/`ClipPath`); garis putus warna `outline`. Seluruh kartu dapat diketuk (ke Detail).
- **StatusChip**: pil kecil (label 12/600, radius penuh) dengan ikon opsional. Status:
  | Konteks | Status | Warna chip |
  |---|---|---|
  | Giveaway | Segera dimulai | info |
  | Giveaway | Aktif | sukses |
  | Giveaway | Draw segera / Menunggu draw | peringatan |
  | Giveaway | Selesai | netral |
  | Tiket | Berpeluang / Menunggu draw | info / peringatan |
  | Tiket | Menang | sukses (+ ikon piala) |
  | Tiket | Tidak terpilih | netral |
  | Verifikasi | Terverifikasi | sukses; Tidak cocok | error |
  Status tidak boleh hanya dibedakan warna: selalu ada teks (dan ikon bila perlu).
- **PrimaryButton**: tinggi 52, radius 12, isi `primary`, teks putih 16/600; keadaan loading (spinner kecil, tombol nonaktif, mencegah kirim ganda). Varian: sekunder (outline), teks.
- **SectionHeader**: judul bagian (subtitle) + aksi opsional ("Lihat semua") di kanan.
- **EmptyState**: ikon besar (64), judul, penjelasan satu kalimat, satu aksi. **ErrorState**: sama, dengan pesan jelas dan tombol "Coba lagi"; pesan "Server sedang bangun, tunggu sebentar..." bila menunggu > 5 detik.
- **SkeletonLoader**: blok abu `surfaceVariant` dengan kilau halus, bentuk menyerupai kartu yang dimuat. Jangan spinner penuh layar untuk daftar.
- **CategoryBanner**: gambar bila ada URL; bila tidak, gradien kategori + ikon (lihat 3.3). Rasio 16:9 (kartu) atau tinggi 180 (Detail). Tidak pernah kotak kosong.
- **Bottom navigation**: 4 item lebar sama, urutan Home, Profil, Saran & Kesan, Logout; tanpa FAB. Ikon 24 + label 12, tinggi bar 64 (`kNavBarHeight`), tiap item >= 48 dp dengan `Semantics` (tombol, terpilih). Terpilih = `primary` + pil `primaryContainer` di belakang ikon + label tebal (bukan hanya warna). Ikon Profil = foto profil pengguna dalam lingkaran kecil (`UserAvatar`, inisial bila belum ada foto; sumber foto sama dengan layar Profil); terpilih = cincin `primary` 2 dp di sekeliling foto. Label bar dibatasi skala 1,15x dan diperkecil seperlunya (FittedBox) bila masih lebih lebar dari item (1/4 lebar layar), tidak pernah dipotong. Home, Profil, dan Saran & Kesan adalah tab (tombol kembali sistem dari Profil/Saran & Kesan kembali ke Home). **Logout** bukan tab dan tidak pernah terpilih: ketuk membuka dialog konfirmasi ("Keluar dari akun?", Batal / Keluar) yang memakai alur logout yang sudah ada (`AuthController.logout`: hapus token dan data SQLite pengguna). Padding bawah daftar di dalam shell memakai satu konstanta `Spacing.listBottom` (= tinggi bar 64 + 16 = 80 dp), bukan angka literal; layar penuh tanpa bar cukup memakai `Spacing.s16`.
- **Banner offline**: strip tipis di atas konten: "Data offline · diperbarui <waktu>"; warna peringatan lembut.
- **Hitung mundur**: kartu sendiri, angka display (hari/jam/menit/detik), diperbarui hanya saat layar terlihat.

## 5. Panduan per layar
- **Login/Register**: logo/teks merek di atas, satu kartu form, tombol utama lebar penuh, tautan pindah layar di bawah. Pesan error di bawah kolom terkait atau satu banner error di atas tombol (bukan snackbar).
- **Home** (pusat fitur; susunan dari atas): header (sapaan + avatar kecil + lonceng notifikasi), ringkasan ("Kamu punya N tiket", ketuk -> My Tickets), kolom cari (ketuk -> Discover), tombol utama "Input Code" (PrimaryButton lebar penuh; satu-satunya tombol utama di Home), grid "Menu fitur" (SurfaceCard berisi ikon bulat `primaryContainer` + label; 4 kolom bila tiap kotak >= 72 dp dengan memperhitungkan skala font, selain itu 2 kolom; isi: Discover, My Tickets, Asisten, Game, Konverter, Peta), chip kategori (menyaring carousel dan daftar di sisi klien), carousel "Segera draw" dan "Terdekat" (kartu horizontal), bagian "Untuk kamu" (kategori yang diminati dari GET /me/affinity, dimuat sekali; tersembunyi bila kosong; kartu menampilkan chip alasan rekomendasi PRD FR-AI-01: afinitas, draw segera, dan jarak), daftar "Semua giveaway". Carousel memakai data yang sudah dimuat controller; "Terdekat" hanya tampil bila mode Terdekat di Discover sudah aktif (jarak berasal dari sana).
- **Discover**: kolom cari + ikon filter + ikon peta; riwayat pencarian saat fokus kosong; hasil memakai kartu yang sama dengan Home; chip filter aktif dapat dihapus satu per satu.
- **Peta**: peta penuh, kartu ringkas di bawah saat penanda diketuk, atribusi OSM selalu terlihat, tombol "lokasi saya" (kanan atas: menengahkan peta bila posisi sudah ada, selain itu meminta posisi lewat mode Terdekat). Penanda terpilih amber, posisi pengguna hijau (isi besar, bukan teks).
- **Detail Giveaway**: banner, judul + status, nilai hadiah (mata uang pilihan) besar, kartu hitung mundur, info (penyelenggara, jumlah pemenang, tiket terbit, jadwal di zona pilihan; tiga zona lain dibuka lewat "Jadwal draw di zona lain"), bagian "Cara ikut", tombol "Input Code" menempel di bawah. Model giveaway belum punya URL gambar, jadi banner selalu gradien kategori sampai backend menyediakannya.
- **Input Code**: kolom kode besar (monospace, huruf kapital, format otomatis XXXX-XXXX-XXXX), satu tombol; hasil sukses: animasi tiket muncul + nomor tiket besar + tombol "Lihat tiket"; hasil gagal: pesan jelas dari tabel kode error + petunjuk (mis. aktifkan lokasi).
- **My Tickets**: dikelompokkan per giveaway (SectionHeader = nama giveaway), TicketCard per tiket (judul giveaway tidak diulang di kartu: baris utama = hadiah, lalu jadwal draw dan kode); filter status (chip) di atas.
- **Hasil Draw** (dari Detail giveaway selesai, My Tickets, dan notifikasi winner/draw_result): kartu hasil tiketmu (menang = ikon piala + teks "Tiketmu menang!", tidak terpilih = ikon netral + teks), info diundi/jumlah tiket/pemenang, daftar pemenang (nomor tiket + nama tersamar dari server), tombol Cek keaslian. Peserta yang membuka hasil BARU melihat dulu layar "Goyangkan untuk melihat hasil" (sensor percepatan, ambang ~14 m/s2, tiga ayunan dalam 1,2 detik) dengan tombol alternatif "Lihat hasil" yang selalu ada; penanda sudah-dilihat disimpan per pengguna di app_settings. Pengungkapan fade/scale 250 ms + konfeti ringan bila menang; keduanya hilang bila animasi dikurangi.
- **Cek keaslian**: empat langkah awam (seed dikunci sebelum tiket, rantai hash tersambung, seed cocok komitmen, pemenang dihitung ulang), tiap langkah Lulus/Gagal/Belum dicek dengan StatusChip + ikon, hash dipotong (8 awal + 8 akhir) dengan tombol salin, lalu ringkasan Terverifikasi / Tidak cocok / Belum diundi. Semua hash dihitung di perangkat (core/verify/chain_verifier.dart, identik dengan backend).
- **Notifikasi**: lonceng di header Home (lencana jumlah belum dibaca, "9+" bila lebih; dimuat saat Home dibuka dan app kembali ke foreground, tanpa polling) membuka daftar; belum dibaca = chip "Belum dibaca" + judul tebal + ikon berwarna; ikon + label per jenis (Menang, Draw selesai, Tiket baru, Pengingat, Info); ketuk membuka Detail Giveaway bila ada giveaway_id. Hasil draw: sebelum reveal satu baris netral ("Hasil draw sudah keluar"); sesudah reveal dua baris dari satu notifikasi (baris hasil dengan chip Menang / Tidak terpilih di atas, baris netral tetap), keduanya membuka Hasil Draw; lencana tidak dihitung ganda.
- **Notifikasi sistem** (bilah status HP; lokal, tanpa FCM): tiket baru ("Tiket #000012 terbit untuk {giveaway}."), pengingat 1 jam sebelum draw dan saat draw ("Draw {giveaway} sudah dijalankan. Buka aplikasi untuk melihat hasilnya."), dan notifikasi server baru (hasil draw/pemenang) saat aplikasi dibuka atau kembali ke foreground, plus pemeriksaan latar Android ~15 menit. Saluran "Tiket dan hasil draw". Izin notifikasi (Android 13+) tidak pernah diminta langsung: dialog "Aktifkan notifikasi?" (Nanti / Lanjutkan) dulu, sekali saat Home pertama dibuka atau saat saklar Pengaturan dinyalakan. Ketuk notifikasi membuka Detail Giveaway, Hasil Draw, atau pusat notifikasi.
- **Pengaturan**: kartu Mata uang, Zona waktu, **Notifikasi**, Keamanan. Notifikasi = saklar "Notifikasi pengingat" (bawaan aktif; mematikan membatalkan semua jadwal) + baris status izin (ikon + teks "diizinkan / belum diizinkan", bukan hanya warna) dan tombol "Buka pengaturan sistem" bila belum diizinkan.
- **Admin** (menu di Profil hanya untuk role admin; server tetap penentu): daftar giveaway -> Buat Giveaway (form, jadwal WIB, draw harus di masa depan), Generate Code (hasil sekali, salin per kode/semua), Daftar Kode (chip Belum dipakai/Dipakai), Draw manual (dialog konfirmasi tidak bisa dibatalkan).
- **Verifikasi draw** (M6): timeline vertikal: 1 Seed dikunci (commit), 2 Periode tiket, 3 Draw dijalankan, 4 Seed dibuka, 5 Hasil terverifikasi. Tiap langkah: ikon status, judul, waktu, dan "Lihat hash" (hash ditampilkan dipotong dengan tombol salin). Hasil akhir: banner "Terverifikasi" (sukses) atau "Tidak cocok" (error) dengan alasan.
- **Pemenang**: daftar tiket pemenang (nomor tiket + inisial/nama samaran sesuai aturan privasi PRD), tanpa mengungkap data pribadi.
- **Profil** (tab): avatar besar (ketuk untuk ganti), nama, username/email, lingkaran level + bar XP, grid lencana (terkunci = abu + gembok), daftar menu (Pengaturan; Admin hanya untuk role admin). Saran & Kesan dan Logout ada di bottom navigation, Konverter dan Game di menu fitur Home: tidak diulang di Profil. Bar XP: XP di dalam level dari 500 XP per level (`level = xp / 500 + 1`, skema database).
- **Pola layar fitur penuh**: Discover, My Tickets, Asisten, Input Code, Game, Konverter, dan Peta dibuka dari Home dengan `context.push` sebagai layar penuh: AppBar dengan tombol kembali, tanpa bottom navigation; tombol kembali sistem Android kembali ke Home. Layar yang berpindah ke layar fitur lain dari dalam layar fitur memakai `pushReplacement` (mis. "Lihat tiket") supaya Home tetap di bawah tumpukan. Saran & Kesan adalah layar akar (tab, tanpa tombol kembali).
- **Konverter**: dua tab; hasil besar di atas, kolom di bawah; keterangan kurs/tanggal dan label offline di kaki.
- **Chat AI / layar Asisten** (M7b; layar fitur penuh dari Home): AppBar "Asisten" dengan tombol "Hapus percakapan" (ikon tempat sampah, dialog konfirmasi, nonaktif bila kosong atau sedang mengirim). Daftar terbalik (terbaru di bawah, menempel ke bawah): pesan sambutan selalu paling atas, 3 saran cepat (chip, hanya selama percakapan masih kosong; ketuk = kirim). Gelembung pengguna di kanan (`primary`, teks `onPrimary`), asisten di kiri (`surface` + garis `outline`), radius 16 dengan sudut ekor 4, lebar maks. 80% layar. Jawaban rekomendasi diikuti kartu giveaway `compact` (maks. 3, lebar maks. 90%) yang membuka Detail Giveaway. Indikator mengetik = gelembung asisten berisi tiga titik berdenyut bergantian (statis bila animasi dikurangi) + "Server sedang bangun..." bila lambat. Kolom input di dasar (1-4 baris, penghitung `n/500` dalam code point, merah dan tombol kirim nonaktif bila lebih), tombol kirim ikon 48 dp nonaktif saat kosong/terlalu panjang/sedang mengirim. Galat = `InlineMessage` (error) di sisi asisten dengan pesan Indonesia per kode (ai_unavailable, rate_limited, daily_limit, ai_not_configured, jaringan) dan tombol teks "Kirim ulang" hanya pada galat terakhir; galat tidak disimpan. Sesi tidak valid (401) tidak menampilkan galat: alur logout yang ada. Riwayat tersimpan di SQLite per pengguna (maks. 200 pesan, dihapus saat logout); ke server hanya 6 giliran terakhir yang terjawab.
- **Buru Kode** (M7a, bertema kode -> tiket -> draw; layar fitur penuh, tanpa bottom navigation; Home > Menu fitur > Buru Kode): hub berisi petunjuk, baris "Latihan untuk: {judul}" (giveaway aktif milik pengguna, kalau tidak ada teratas "Untuk kamu", dari data yang sudah dimuat/cache, tanpa permintaan jaringan; tanpa data = teks generik; ikon+gradien kategori dari CategoryStyle) dan pilihan tingkat (Mudah 6x6, Sedang 8x8, Sulit 10x10; segmen kode dan waktu <= batas server 30 / 60 detik). Permainan: bola = chip kode, item koleksi (bintang) = segmen kode 4 karakter (A-Z, 0-9), titik akhir = Mesin Undian (ikon tiket). HUD: waktu, hitungan segmen, dan kode XXXX-XXXX-XXXX yang terisi bertahap (slot kosong "····", 3 segmen per baris; jumlah segmen = jumlah item; tiap baris mengecil bila perlu, tidak terpotong di 320 dp / font 1,3x; Semantics mengeja segmen terisi). Kontrol tidak berubah: kemiringan (gyroscope + accelerometer), D-pad selalu ada, label sensor + "Kalibrasi ulang" (Wrap supaya tidak meluap). Hasil sukses: "Tiket Latihan terbit!" memakai TicketCard (nomor `TL-xxxx`, kode rakitan, chip "Latihan", kategori giveaway target), label tegas "Tiket latihan: tidak memengaruhi peluang menang", chip +XP dan lencana baru (versi server). Kode latihan deterministik dari seed level (code_hunt.dart) dan karakter pertama selalu I/O/0/1 (tidak ada di alfabet kode asli) sehingga bukan kode valid. Gagal (waktu habis): segmen yang sempat terkumpul + pesan kode belum lengkap. Skor tetap dikirim sekali ke POST /game/scores (stars/cleared/skor tidak berubah; tanpa retry; gagal -> pesan + "Kirim skor").
- **Pemilih game** (Home > Menu fitur > Game; AppBar "Pilih game", rute /game): dua kartu besar (SurfaceCard raised, ikon bulat primaryContainer, judul, satu kalimat, chip). Buru Kode: chip "Sensor: gyroscope + accelerometer" dan rekor lokal ("Rekor N · tingkat X selesai" / "Belum ada rekor"; app_settings `codehunt_best`, hanya tampilan). Rakit Rantai: chip "Puzzle hash-chain" dan "x/5 level selesai". Tautan teks kecil "Papan peringkat Buru Kode". Ketuk kartu = push ke /game/codehunt atau /game/chain; kembali ke pemilih.
- **Hub Buru Kode** (/game/codehunt, AppBar "Buru Kode"): petunjuk, "Latihan untuk", pilihan tingkat, tombol Papan peringkat (skor milik Buru Kode).
- **Rakit Rantai** (game kedua, latihan konsep hash-chain; rute /game/chain dan /game/chain/play): daftar 5 level (chip "Selesai · terbaik N langkah" atau "Belum selesai"), semua terbuka. Kartu "Cara main" di atas tiap mode (primaryContainer), terbuka otomatis pada kunjungan pertama per mode (app_settings `chain_howto_arrange` / `chain_howto_inspect`, per pengguna) dan dibuka lagi lewat ikon ? di AppBar. Level 1-3 mode Susun (3, 4, 5 block): ReorderableListView dengan gagang seret + tombol naik/turun 48 dp, hitungan langkah, "Cek Rantai" menandai tiap block "Posisi benar"/"Posisi salah" (StatusChip ikon + teks). Level 4-5 mode Periksa (5, 6 block): rantai berurutan; block t (bukan terakhir) diubah dan hash-nya dihitung ulang, sehingga hanya sambungan t -> t+1 yang putus (prev block t+1 masih hash lama). Antar dua block ada konektor ketuk 48 dp "Sambungan putus?" (status teks + ikon: belum diperiksa / "Sambungan cocok" / "Sambungan putus"). Pemain membandingkan `prev:` dan `hash:` (8 hex) lalu mengetuk konektor. Benar: penjelasan "Block {t} diubah, hash barunya {x} tidak lagi sama dengan yang tersimpan di block berikutnya ({y})…"; salah: petunjuk + coba lagi, tombol "Petunjuk" setelah 2 salah menyorot dua block ("Periksa di sini"). Semantics per block dan per konektor. Setelah menang: kartu penjelasan Verifikasi + langkah terbaik. Progres di app_settings `chain_progress` per pengguna (JSON level -> langkah terbaik); tanpa XP/lencana/skor server. Data deterministik per level (chain_puzzle.dart), hash = SHA-256(prev|payload) lewat sha256Hex.
- **Papan peringkat** (dari hasil game dan Menu fitur Home): skor total 7 hari terakhir dari server; 3 teratas berikon piala, baris pengguna berlatar primaryContainer + chip "Kamu" + ikon (bukan hanya warna); skeleton/kosong/galat dan tarik untuk muat ulang.
- **Admin** (M5b): daftar giveaway dengan chip status, formulir bertahap, aksi berbahaya (draw demo) memakai dialog konfirmasi dengan teks jelas.

## 6. Bahasa dan format
- Bahasa Indonesia, nada ramah dan singkat. Tombol berupa kata kerja ("Masukkan kode", "Lihat tiket"). Pesan error menyebut apa yang terjadi dan apa yang bisa dilakukan.
- Mata uang: `Rp 21.587.000`, `US$1.200,00`, `€1.068,14`, `¥189.672` (IDR/JPY tanpa desimal). Tanggal: `19 Okt 2026, 03.42 WIB`. Nomor tiket tetap tabular.
- Jangan menampilkan data teknis mentah (UUID, kode error) ke pengguna; tampilkan di mode detail untuk verifikasi saja.
- Glosarium (satu istilah per hal, jangan diganti sinonim):
  - Nama fitur utama tetap: My Tickets, Discover, Input Code (tombol Input Code di Home).
  - Status tiket: Berpeluang, Menunggu draw, Menang, Tidak terpilih. Peran: Admin, Pengguna.
  - Cek Keaslian = layar/tombol/judul untuk memeriksa hash-chain undian; "Terverifikasi" hanya chip hasilnya. Kata "verifikasi" tidak dipakai di tombol.
  - Kunci biometrik = kunci aplikasi dengan sidik jari, wajah, atau PIN perangkat; di layar kunci, jalan keluar bernama "Masuk dengan password" (logout).
  - Home adalah pusat fitur; layar fitur dibuka dari Home, bukan "tab" atau "tombol di tengah".

## 7. Aksesibilitas
- Kontras teks >= 4,5:1 (>= 3:1 untuk teks besar >= 18 dp / tebal >= 14 dp). Periksa di kedua tema.
- Status tidak hanya dengan warna. `Semantics` label pada tombol ikon (filter, peta, tutup, salin) dan semua item bottom navigation.
- Urutan fokus mengikuti urutan baca. Skala font 1,3x tanpa teks terpotong. Hormati pengaturan "kurangi animasi".

## 8. Yang dihindari
- Gaya inline berulang (warna/ukuran literal di widget) alih-alih token.
- Spinner penuh layar untuk daftar; daftar kosong tanpa penjelasan; error tanpa tombol coba lagi.
- Teks amber/hijau muda di atas putih; teks di atas gambar tanpa lapisan gelap.
- Lebih dari satu tombol utama per layar; dialog untuk hal yang bisa dibatalkan (pakai snackbar + "Urungkan").
- Menyalin aset, logo, atau tata letak persis dari aplikasi lain.

## 9. Daftar periksa sebelum commit layar UI
- [ ] Memakai token dan komponen bersama; tidak ada warna/ukuran literal baru.
- [ ] Loading, kosong, error, dan offline ada dan terlihat benar.
- [ ] Terang dan gelap sama-sama terbaca; kontras terpenuhi.
- [ ] 360 dp, 428 dp, dan skala font 1,3x tanpa overflow.
- [ ] Label semantik pada tombol ikon; target sentuh >= 48 dp.
- [ ] `flutter analyze --no-pub` dan `flutter test` bersih.
