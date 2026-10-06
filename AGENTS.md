Kamu adalah senior Flutter engineer. Kita membangun aplikasi mobile "Code2Ticket".

KONSEP
Pengguna memasukkan kode partisipasi dari campaign eksternal. Sistem memvalidasi
kode, lalu membuat tiket undian digital bernomor unik. Tiket menunggu waktu draw,
pemenang ditentukan, dan hasilnya diverifikasi lewat blockchain. Aplikasi TIDAK
membuat campaign eksternal.
Alur: CODE → TICKET → DRAW → WINNER.

TECH STACK
- Flutter (Dart), Android + iOS
- Database: Supabase PostgreSQL (HANYA sebagai database online)
- Login & session: custom logic di Dart, TANPA auth service pihak ketiga
  (tidak boleh Supabase Auth/Firebase Auth). Password disimpan sebagai hash.
- Peta/LBS: OpenStreetMap + Nominatim (flutter_map, geolocator)
- Currency: Frankfurter API
- Timezone: TimeZoneDB atau data timezone lokal (package timezone)
- Cuaca (opsional): Open-Meteo
- LLM: API dengan free tier
- Blockchain: local chain (Hardhat/Anvil), hanya untuk bukti hasil draw,
  BUKAN database utama
- Sensor: accelerometer (shake to reveal), gyroscope (mini game)

ATURAN KETAT
- Sensor dan game TIDAK memengaruhi peluang menang.
- Arsitektur: feature-first (lib/features/<fitur>/{data,domain,presentation}),
  state management Riverpod, routing go_router.
- Jangan hardcode secret; pakai file .env (flutter_dotenv) dan masukkan ke .gitignore.
- Semua teks UI dalam Bahasa Indonesia, kode & komentar dalam Bahasa Inggris.
- Setiap langkah harus compile dan jalan sebelum lanjut. Jalankan `flutter analyze`
  setelah perubahan.
- Kerjakan HANYA langkah yang diminta, jangan loncat ke fitur lain.

MENU: Home, Discover, Input Code, My Tickets, Draw, Game, AI Assistant, Profile.

TABEL: users, giveaways, codes, tickets, draws, winners, notifications,
user_activity, game_scores.
