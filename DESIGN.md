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
| Home | Home Gojek / GoPay | Sapaan, ringkasan tiket, kolom cari, chip kategori, carousel horizontal, daftar |
| Tombol tengah | Tombol scan e-wallet (DANA, LinkAja, GoPay) | FAB "Input Code" bulat, melayang di atas bar |
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

### 3.3 Warna kategori (banner tanpa gambar)
Gradien dua warna per kategori + ikon: gaming `#4F46E5→#7C3AED` (ikon gamepad), travel `#0EA5E9→#22D3EE` (pesawat), elektronik `#334155→#64748B` (laptop/chip),
fashion `#DB2777→#F472B6`, makanan `#EA580C→#FB923C`, lainnya `#4F46E5→#818CF8`. Teks putih di atas gradien harus kontras >= 4,5 (pakai lapisan gelap 20% bila perlu).
Kategori yang tidak dikenal memakai "lainnya". Warna per kategori konsisten di seluruh aplikasi.

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
- Radius: 8 (chip kecil, input), 12 (tombol), 16 (kartu), 24 (sheet atas), penuh (FAB, avatar).
- Bayangan: kartu `0 2 8 rgba(15,23,42,0.06)`; kartu terangkat `0 6 16 rgba(15,23,42,0.10)`; FAB `0 8 20 rgba(79,70,229,0.35)`. Mode gelap: kurangi bayangan, andalkan beda warna surface.
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
  | Tiket | Eligible / Menunggu draw | info / peringatan |
  | Tiket | Menang | sukses (+ ikon piala) |
  | Tiket | Tidak terpilih | netral |
  | Verifikasi | Terverifikasi | sukses; Tidak cocok | error |
  Status tidak boleh hanya dibedakan warna: selalu ada teks (dan ikon bila perlu).
- **PrimaryButton**: tinggi 52, radius 12, isi `primary`, teks putih 16/600; keadaan loading (spinner kecil, tombol nonaktif, mencegah kirim ganda). Varian: sekunder (outline), teks.
- **SectionHeader**: judul bagian (subtitle) + aksi opsional ("Lihat semua") di kanan.
- **EmptyState**: ikon besar (64), judul, penjelasan satu kalimat, satu aksi. **ErrorState**: sama, dengan pesan jelas dan tombol "Coba lagi"; pesan "Server sedang bangun, tunggu sebentar..." bila menunggu > 5 detik.
- **SkeletonLoader**: blok abu `surfaceVariant` dengan kilau halus, bentuk menyerupai kartu yang dimuat. Jangan spinner penuh layar untuk daftar.
- **CategoryBanner**: gambar bila ada URL; bila tidak, gradien kategori + ikon (lihat 3.3). Rasio 16:9 (kartu) atau tinggi 180 (Detail). Tidak pernah kotak kosong.
- **Bottom navigation**: 5 tab lebar sama (Home, Discover, My Tickets, Asisten, Profil), ikon 24 + label 12; aktif = `primary` + indikator. FAB "Input Code" melayang di tengah, 10 dp di atas bar, tidak menutupi label tab ke-3; padding bawah daftar >= 140 dp.
- **Banner offline**: strip tipis di atas konten: "Data offline · diperbarui <waktu>"; warna peringatan lembut.
- **Hitung mundur**: kartu sendiri, angka display (hari/jam/menit/detik), diperbarui hanya saat layar terlihat.

## 5. Panduan per layar
- **Login/Register**: logo/teks merek di atas, satu kartu form, tombol utama lebar penuh, tautan pindah layar di bawah. Pesan error di bawah kolom terkait atau satu banner error di atas tombol (bukan snackbar).
- **Home**: header (sapaan + avatar kecil), ringkasan ("Kamu punya N tiket", ketuk -> My Tickets), kolom cari (ketuk -> Discover), chip kategori, carousel "Segera draw" dan "Terdekat" (kartu horizontal), daftar "Semua giveaway".
- **Discover**: kolom cari + ikon filter + ikon peta; riwayat pencarian saat fokus kosong; hasil memakai kartu yang sama dengan Home; chip filter aktif dapat dihapus satu per satu.
- **Peta**: peta penuh, kartu ringkas di bawah saat penanda diketuk, atribusi OSM selalu terlihat, tombol "lokasi saya".
- **Detail Giveaway**: banner, judul + status, nilai hadiah (mata uang pilihan) besar, kartu hitung mundur, info (penyelenggara, jumlah pemenang, tiket terbit, jadwal di zona pilihan + tiga zona lain dapat dibuka), bagian "Cara ikut", tombol "Input Code" menempel di bawah.
- **Input Code**: kolom kode besar (monospace, huruf kapital, format otomatis XXXX-XXXX-XXXX), satu tombol; hasil sukses: animasi tiket muncul + nomor tiket besar + tombol "Lihat tiket"; hasil gagal: pesan jelas dari tabel kode error + petunjuk (mis. aktifkan lokasi).
- **My Tickets**: dikelompokkan per giveaway (SectionHeader = nama giveaway), TicketCard per tiket; filter status (chip) di atas.
- **Verifikasi draw** (M6): timeline vertikal: 1 Seed dikunci (commit), 2 Periode tiket, 3 Draw dijalankan, 4 Seed dibuka, 5 Hasil terverifikasi. Tiap langkah: ikon status, judul, waktu, dan "Lihat hash" (hash ditampilkan dipotong dengan tombol salin). Hasil akhir: banner "Terverifikasi" (sukses) atau "Tidak cocok" (error) dengan alasan.
- **Pemenang**: daftar tiket pemenang (nomor tiket + inisial/nama samaran sesuai aturan privasi PRD), tanpa mengungkap data pribadi.
- **Profil**: avatar besar (ketuk untuk ganti), nama, username, lingkaran level + bar XP, grid lencana (terkunci = abu), daftar menu (Konverter, Saran & Kesan, Pengaturan, Keluar; Admin hanya untuk role admin).
- **Konverter**: dua tab; hasil besar di atas, kolom di bawah; keterangan kurs/tanggal dan label offline di kaki.
- **Chat AI** (M7): gelembung kiri/kanan, indikator mengetik, saran cepat (chip) di atas input; jawaban rekomendasi menyertakan kartu giveaway yang dapat diketuk.
- **Game** (M7): layar penuh, papan skor di atas, hasil dengan bintang; tidak memakai komponen tab/FAB.
- **Admin** (M5b): daftar giveaway dengan chip status, formulir bertahap, aksi berbahaya (draw demo) memakai dialog konfirmasi dengan teks jelas.

## 6. Bahasa dan format
- Bahasa Indonesia, nada ramah dan singkat. Tombol berupa kata kerja ("Masukkan kode", "Lihat tiket"). Pesan error menyebut apa yang terjadi dan apa yang bisa dilakukan.
- Mata uang: `Rp 21.587.000`, `US$1.200,00`, `€1.068,14`, `¥189.672` (IDR/JPY tanpa desimal). Tanggal: `19 Okt 2026, 03.42 WIB`. Nomor tiket tetap tabular.
- Jangan menampilkan data teknis mentah (UUID, kode error) ke pengguna; tampilkan di mode detail untuk verifikasi saja.

## 7. Aksesibilitas
- Kontras teks >= 4,5:1 (>= 3:1 untuk teks besar >= 18 dp / tebal >= 14 dp). Periksa di kedua tema.
- Status tidak hanya dengan warna. `Semantics` label pada tombol ikon (FAB, filter, peta, tutup, salin).
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
