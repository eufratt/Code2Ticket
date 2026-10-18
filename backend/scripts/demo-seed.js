// Membuat data demo lewat API (bukan SQL langsung): 2 giveaway aktif + 10 kode tiap giveaway.
//
//   API_BASE_URL=... ADMIN_USERNAME=... ADMIN_PASSWORD=... npm run demo-seed
//
// Kredensial hanya dibaca dari env (tidak ditulis ke file). Kode dicetak ke terminal saja.
// Menjalankannya ulang membuat giveaway demo baru (judul sama, id berbeda).
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
    title: 'Demo: Laptop Gaming Giveaway', category: 'gaming', organizer: 'Code2Ticket Demo',
    description: 'Giveaway demo tanpa batas lokasi.', prize_name: 'Laptop Gaming 15"', prize_value_usd: 1200,
    winner_count: 3, max_tickets_per_user: 5, start_at: hours(-0.1), end_at: hours(3), draw_at: hours(4),
  },
  {
    title: 'Demo: Paket Liburan Bali', category: 'travel', organizer: 'Code2Ticket Demo',
    description: 'Giveaway demo bertema travel.', prize_name: 'Paket 3 hari 2 malam Bali', prize_value_usd: 800,
    latitude: -8.4095, longitude: 115.1889, address: 'Bali, Indonesia',
    winner_count: 2, max_tickets_per_user: 5, start_at: hours(-0.1), end_at: hours(5), draw_at: hours(6),
  },
];

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
    const g = must(await call('POST', '/admin/giveaways', { token, body: d }), `Buat "${d.title}"`);
    const c = must(await call('POST', `/admin/giveaways/${g.giveaway_id}/codes`, { token, body: { count: 10 } }), 'Buat kode');
    console.log(`\n${d.title}  (id ${g.giveaway_id})`);
    console.log(`  draw: ${d.draw_at}`);
    for (const code of c.codes) console.log(`  ${code}`);
  }
  await call('POST', '/auth/logout', { token }).catch(() => {});
  console.log('\nSelesai. Kode hanya tampil di sini; salin sekarang.');
} catch (e) {
  console.error(`Gagal: ${e.message}`);
  process.exit(1);
}
