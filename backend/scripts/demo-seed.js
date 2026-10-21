// Membuat data demo lewat API (bukan SQL langsung): giveaway aktif + kode tiap giveaway.
//
//   API_BASE_URL=... ADMIN_USERNAME=... ADMIN_PASSWORD=... npm run demo-seed
//
// Kredensial hanya dibaca dari env (tidak ditulis ke file). Kode dicetak ke terminal saja.
// Seed bersifat idempotent: jika dijalankan ulang, giveaway yang masih aktif digunakan kembali
// dan kode yang belum terpakai dicetak ulang (menambah kode baru jika kurang dari 10).
import crypto from 'node:crypto';

const { API_BASE_URL, ADMIN_USERNAME, ADMIN_PASSWORD } = process.env;
const missing = ['API_BASE_URL', 'ADMIN_USERNAME', 'ADMIN_PASSWORD'].filter((k) => !process.env[k]);
if (missing.length) {
  console.error(`Env belum diisi: ${missing.join(', ')}`);
  process.exit(2);
}
let base;
try {
  base = new URL(API_BASE_URL).origin + new URL(API_BASE_URL).pathname.replace(/\/+$/, '');
} catch {
  console.error('API_BASE_URL bukan URL yang valid.');
  process.exit(2);
}

// Server gratis (Render) bisa butuh ~1 menit untuk bangun pada permintaan pertama.
async function call(method, path, { token, body } = {}) {
  const res = await fetch(base + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(120_000),
  });
  const json = await res.json().catch(() => ({}));
  if (res.status === 401 || res.status === 403) throw new Error(`${path}: ditolak (HTTP ${res.status}). Akun harus admin.`);
  if (!res.ok && !('ok' in json)) throw new Error(`${path}: HTTP ${res.status}`);
  return json;
}
const must = (r, what) => {
  if (r.ok !== true) throw new Error(`${what} gagal: ${r.error ?? 'tidak diketahui'}${r.field ? ` (${r.field})` : ''}`);
  return r;
};

// Kontrak klien (docs README bagian 1): salt dipakai sebagai teks UTF-8.
const clientHash = (password, salt) => crypto.pbkdf2Sync(password, salt, 10_000, 32, 'sha256').toString('hex');

const hours = (h) => new Date(Date.now() + h * 3_600_000).toISOString();
const DEMOS = [
  {
    title: 'Demo: Laptop Gaming Giveaway',
    category: 'gaming',
    organizer: 'Code2Ticket Demo',
    description: 'Giveaway demo online tanpa batas lokasi. Kode dapat ditukarkan dari mana saja.',
    prize_name: 'Laptop Gaming 15"',
    prize_value_idr: 20_000_000,
    how_to_participate: 'Ikuti akun Instagram @code2ticket.demo dan cari kode di unggahan pinned. Kode berlaku sekali pakai.',
    organizer_url: 'https://example.com/code2ticket-demo',
    winner_count: 3,
    max_tickets_per_user: 5,
    start_at: hours(-0.1),
    end_at: hours(4),
    draw_at: hours(5),
  },
  {
    title: 'Demo: Paket Liburan Bali',
    category: 'travel',
    organizer: 'Code2Ticket Demo',
    description: 'Giveaway demo bertema travel dengan koordinat lokasi tanpa batas radius (seluruh Indonesia).',
    prize_name: 'Paket 3 hari 2 malam Bali',
    prize_value_idr: 14_000_000,
    how_to_participate: 'Kode dibagikan di stan Biro Wisata Demo dan di halaman penyelenggara.',
    organizer_url: 'https://example.com/paket-bali',
    latitude: -8.4095,
    longitude: 115.1889,
    address: 'Denpasar, Bali, Indonesia',
    winner_count: 2,
    max_tickets_per_user: 5,
    start_at: hours(-0.1),
    end_at: hours(6),
    draw_at: hours(7),
  },
  {
    title: 'Demo: Voucher Kuliner Tunjungan Surabaya',
    category: 'food',
    organizer: 'Surabaya Culinary Fest',
    description: 'Voucher kuliner khusus area Surabaya dan sekitarnya. Penukaran kode membutuhkan verifikasi lokasi (radius 15 km).',
    prize_name: 'Voucher Kuliner Surabaya Rp 500.000',
    prize_value_idr: 500_000,
    how_to_participate: 'Beli minimal satu menu di tenant peserta, kode tercetak di struk pembelian.',
    latitude: -7.2575,
    longitude: 112.7521,
    address: 'Jl. Tunjungan, Genteng, Surabaya, Jawa Timur',
    radius_km: 15,
    winner_count: 2,
    max_tickets_per_user: 5,
    start_at: hours(-0.1),
    end_at: hours(6),
    draw_at: hours(7),
  },
  {
    title: 'Demo: Smartphone Flagship Jakarta Pusat',
    category: 'tech',
    organizer: 'Jakarta Tech Expo',
    description: 'Smartphone flagship untuk area Jakarta Pusat dan sekitarnya. Penukaran kode dibatasi radius 10 km dari Monas.',
    prize_name: 'Smartphone Flagship 256GB',
    prize_value_idr: 15_000_000,
    how_to_participate: 'Kunjungi booth Jakarta Tech Expo dan pindai kode di layar demo untuk mendapat kode tukar.',
    organizer_url: 'https://example.com/jakarta-tech-expo',
    latitude: -6.1754,
    longitude: 106.8272,
    address: 'Monas, Gambir, Jakarta Pusat, DKI Jakarta',
    radius_km: 10,
    winner_count: 1,
    max_tickets_per_user: 5,
    start_at: hours(-0.1),
    end_at: hours(8),
    draw_at: hours(9),
  },
  {
    title: 'Demo: Sneaker Exhibition Jakarta Selatan',
    category: 'fashion',
    organizer: 'SneakerCon Jakarta',
    description: 'Sepasang sneaker limited edition khusus area SCBD Jakarta Selatan (radius 12 km).',
    prize_name: 'Sneaker Limited Edition',
    prize_value_idr: 4_500_000,
    how_to_participate: 'Kode dibagikan petugas SneakerCon di pintu masuk pameran SCBD.',
    latitude: -6.2255,
    longitude: 106.8095,
    address: 'SCBD, Kebayoran Baru, Jakarta Selatan, DKI Jakarta',
    radius_km: 12,
    winner_count: 2,
    max_tickets_per_user: 5,
    start_at: hours(-0.1),
    end_at: hours(10),
    draw_at: hours(11),
  },
];

const TARGET_CODES = 10;

try {
  console.log(`Menghubungi ${base} (bisa lama bila server sedang tidur)...`);
  const { salt } = must(await call('POST', '/auth/salt', { body: { identifier: ADMIN_USERNAME } }), 'Ambil salt');
  const login = must(
    await call('POST', '/auth/login', { body: { identifier: ADMIN_USERNAME, password_hash: clientHash(ADMIN_PASSWORD, salt) } }),
    'Login admin',
  );
  if (login.user?.role !== 'admin') throw new Error('Akun ini bukan admin.');
  const token = login.token;

  for (const d of DEMOS) {
    // 1. Cari giveaway yang sudah ada (idempotent: gunakan kembali jika belum di-draw)
    const searchRes = await call('GET', `/giveaways?q=${encodeURIComponent(d.title)}&status=all`, { token });
    const existingList = Array.isArray(searchRes) ? searchRes : [];
    const existing = existingList.find((g) => g.title === d.title && g.status !== 'drawn');

    let giveawayId;
    let drawAt = d.draw_at;
    let isNew = false;

    if (existing) {
      giveawayId = existing.id;
      drawAt = existing.draw_at;

      // Jika waktu berakhir sudah lewat atau sisa kurang dari 30 menit, perpanjang waktu aktifnya
      const endMs = new Date(existing.end_at).getTime();
      if (Number.isFinite(endMs) && endMs <= Date.now() + 30 * 60 * 1000) {
        await call('POST', '/admin/giveaways', {
          token,
          body: {
            id: giveawayId,
            end_at: d.end_at,
            draw_at: d.draw_at,
          },
        });
        drawAt = d.draw_at;
      }
    } else {
      isNew = true;
      const g = must(await call('POST', '/admin/giveaways', { token, body: d }), `Buat "${d.title}"`);
      giveawayId = g.giveaway_id;
    }

    // 2. Periksa kode yang ada untuk giveaway ini
    const codesRes = await call('GET', `/admin/giveaways/${giveawayId}/codes`, { token });
    const existingCodes = Array.isArray(codesRes) ? codesRes : [];
    const unusedCodes = existingCodes.filter((c) => !c.is_used);

    let activeCodes = unusedCodes.map((c) => c.code);

    // 3. Tambah kode baru jika kode belum terpakai kurang dari target
    if (unusedCodes.length < TARGET_CODES) {
      const needed = TARGET_CODES - unusedCodes.length;
      const codeBody = { count: needed };
      if (d.radius_km && d.latitude != null && d.longitude != null) {
        codeBody.geo_lat = d.latitude;
        codeBody.geo_lng = d.longitude;
        codeBody.geo_radius_km = d.radius_km;
      }
      const c = must(await call('POST', `/admin/giveaways/${giveawayId}/codes`, { token, body: codeBody }), 'Buat kode');
      activeCodes = [...activeCodes, ...c.codes];
    } else {
      activeCodes = activeCodes.slice(0, TARGET_CODES);
    }

    console.log(`\n${d.title} (id: ${giveawayId}) [${isNew ? 'baru' : 'aktif/idempotent'}]`);
    console.log(`  kategori: ${d.category} | draw: ${drawAt}`);
    if (d.radius_km) {
      console.log(`  lokasi: ${d.address} (lat: ${d.latitude}, lng: ${d.longitude}, radius: ${d.radius_km} km)`);
      console.log(`  verifikasi lokasi: WAJIB (dalam radius ${d.radius_km} km)`);
    } else if (d.latitude != null && d.longitude != null) {
      console.log(`  lokasi: ${d.address} (lat: ${d.latitude}, lng: ${d.longitude}) - tanpa batas radius`);
    } else {
      console.log('  lokasi: online (tanpa batas lokasi)');
    }
    console.log(`  kode belum terpakai (${activeCodes.length}):`);
    for (const code of activeCodes) console.log(`    ${code}`);
  }
  await call('POST', '/auth/logout', { token }).catch(() => {});
  console.log('\nSelesai. Kode hanya tampil di sini; salin sekarang.');
} catch (e) {
  console.error(`Gagal: ${e.message}`);
  process.exit(1);
}
