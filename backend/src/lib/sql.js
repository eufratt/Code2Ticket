// Status giveaway menurut waktu SEKARANG. Kolom giveaways.status hanya diperbarui scheduler (tiap menit), jadi bisa basi;
// semua yang ditampilkan ke klien memakai ekspresi ini. 'drawn' selalu menang (satu-satunya status yang tidak diturunkan dari waktu).
export const effectiveStatus = (alias = 'g') =>
  `(case when ${alias}.status = 'drawn' then 'drawn' when now() < ${alias}.start_at then 'upcoming' when now() < ${alias}.end_at then 'active' else 'waiting_draw' end)`;
