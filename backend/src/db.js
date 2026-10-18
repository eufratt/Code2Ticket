import pg from 'pg';

// bigint (ts_ms, count, id) dan numeric (nilai hadiah, jarak) keluar sebagai angka JSON,
// sama seperti hasil to_jsonb() pada fungsi SQL lama. Semua nilai < 2^53.
pg.types.setTypeParser(20, (v) => Number(v));
pg.types.setTypeParser(1700, (v) => Number(v));

export function createPool(config) {
  const ssl = { disable: false, require: { rejectUnauthorized: false }, 'verify-full': { rejectUnauthorized: true } }[
    config.DATABASE_SSL ?? 'disable'
  ];
  const pool = new pg.Pool({ connectionString: config.DATABASE_URL, max: config.DB_POOL_MAX ?? 10, ssl });
  // Error pada koneksi idle tidak boleh menjatuhkan proses.
  pool.on('error', () => {});
  return pool;
}

// Satu transaksi. Commit bila fn selesai (termasuk hasil gagal-bisnis yang dikembalikan,
// supaya pencatatan percobaan gagal tetap tersimpan); rollback hanya bila fn melempar.
export async function withTx(pool, fn) {
  const client = await pool.connect();
  try {
    await client.query('begin');
    const out = await fn(client);
    await client.query('commit');
    return out;
  } catch (e) {
    await client.query('rollback').catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}
