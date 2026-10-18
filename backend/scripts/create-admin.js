// Membuat akun admin pertama (pengganti 05_bootstrap_admin.sql / make_admin_sql.py, yang memanggil
// rpc_register yang sudah dibuang oleh 06_backend.sql).
//
//   ADMIN_PASSWORD='...' node scripts/create-admin.js <username> <email> "<Nama Lengkap>"
//
// Password dibaca dari env supaya tidak masuk riwayat shell sebagai argumen. Hash PBKDF2 dihitung
// persis seperti aplikasi (kontrak README bagian 1), lalu disimpan sebagai bcrypt oleh register().
import 'dotenv/config';
import crypto from 'node:crypto';
import { loadConfig } from '../src/config.js';
import { createPool } from '../src/db.js';
import { register } from '../src/services/auth.js';

const [username, email, fullName] = process.argv.slice(2);
const password = process.env.ADMIN_PASSWORD ?? '';
if (!username || !email || !fullName || password.length < 8) {
  console.error('Pemakaian: ADMIN_PASSWORD=<min 8 karakter> node scripts/create-admin.js <username> <email> "<Nama Lengkap>"');
  process.exit(2);
}

const pool = createPool(loadConfig());
try {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(password, salt, 10_000, 32, 'sha256').toString('hex');
  const r = await register(pool, { username, email, full_name: fullName, salt, password_hash: hash });
  if (!r.ok) {
    console.error(`Gagal membuat akun: ${r.error}${r.field ? ` (${r.field})` : ''}`);
    process.exit(1);
  }
  await pool.query("update users set role = 'admin' where id = $1", [r.user_id]);
  console.log(`Admin dibuat: ${username}`);
} finally {
  await pool.end();
}
